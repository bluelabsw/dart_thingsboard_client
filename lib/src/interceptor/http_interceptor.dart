import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import '../error/thingsboard_error.dart';
import 'interceptor_config.dart';
import '../model/constants.dart';

import '../thingsboard_client_base.dart';

class HttpInterceptor extends Interceptor {
  static const String _authScheme = 'Bearer ';

  final Dio _dio;
  final Dio _internalDio;
  final BaseThingsboardClient _tbClient;
  final String _authHeaderName;
  final void Function() _loadStart;
  final void Function() _loadFinish;
  final void Function(ThingsboardError error) _onError;

  final _internalUrlPrefixes = ['/api/auth/token', '/api/plugins/rpc'];

  int _activeRequests = 0;
  Future<void>? _refreshTokenFuture;

  HttpInterceptor(
      this._dio,
      this._tbClient,
      this._authHeaderName,
      void Function() onLoadStart,
      void Function() onLoadFinish,
      void Function(ThingsboardError error) onError)
      : _internalDio = Dio(BaseOptions(baseUrl: _dio.options.baseUrl)),
        _loadStart = onLoadStart,
        _loadFinish = onLoadFinish,
        _onError = onError;

  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.path.startsWith('/api/')) {
      var config = _getInterceptorConfig(options);
      var isLoading = !_isInternalUrlPrefix(options.path);
      if (!config.isRetry) {
        _updateLoadingState(config, isLoading);
      }
      if (_isTokenBasedAuthEntryPoint(options.path)) {
        if (_tbClient.getJwtToken() == null &&
            !_tbClient.refreshTokenPending()) {
          await _handleRequestError(
              options, handler, ThingsboardError(message: 'Unauthorized!'));
        } else if (!_tbClient.isJwtTokenValid()) {
          await _handleRequestError(
              options, handler, ThingsboardError(refreshTokenPending: true));
        } else {
          await _jwtIntercept(options, handler);
        }
      } else {
        await _handleRequest(options, handler);
      }
    } else {
      handler.next(options);
    }
  }

  Future<void> _jwtIntercept(
      RequestOptions options, RequestInterceptorHandler handler) async {
    if (_updateAuthorizationHeader(options)) {
      await _handleRequest(options, handler);
    } else {
      await _handleRequestError(options, handler,
          ThingsboardError(message: 'Could not get JWT token from store.'));
    }
  }

  Future<void> _handleRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    handler.next(options);
  }

  Future<void> _handleRequestError(RequestOptions options,
      RequestInterceptorHandler handler, ThingsboardError error) async {
    var response =
        Response<ThingsboardError>(requestOptions: options, data: error);
    handler.reject(
      DioException(
        requestOptions: options,
        response: response,
        error: error,
        type: DioExceptionType.badResponse,
      ),
      true,
    );
  }

  @override
  Future<void> onResponse(
      Response response, ResponseInterceptorHandler handler) async {
    var config = _getInterceptorConfig(response.requestOptions);
    if (response.requestOptions.path.startsWith('/api/')) {
      _updateLoadingState(config, false);
    }
    handler.next(response);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    var config = _getInterceptorConfig(err.requestOptions);
    var notify = true;
    var ignoreErrors = config.ignoreErrors;
    var resendRequest = config.resendRequest;
    var tbError = toThingsboardError(err, err.stackTrace);
    var errorCode = tbError.errorCode;
    var refreshToken = false;
    if (tbError.refreshTokenPending == true ||
        err.response?.statusCode == 401) {
      if (tbError.refreshTokenPending == true ||
          errorCode == ThingsBoardErrorCode.jwtTokenExpired) {
        refreshToken = true;
      } else if (errorCode == ThingsBoardErrorCode.credentialsExpired) {
        notify = false;
      }
    }
    if (refreshToken) {
      await _refreshTokenAndRetry(err, handler, config);
      return;
    }
    if (err.response?.statusCode == 429 && resendRequest) {
      await _retryRequestWithTimeout(err, handler);
      return;
    }
    if (err.requestOptions.path.startsWith('/api/')) {
      _updateLoadingState(config, false);
    }
    await _handleError(
        tbError, err.requestOptions, handler, notify && !ignoreErrors);
  }

  Future<void> _refreshTokenAndRetry(DioException error,
      ErrorInterceptorHandler handler, InterceptorConfig config) async {
    final refreshFuture = _refreshTokenFuture ??= _tbClient.refreshJwtToken(
        internalDio: _internalDio, interceptRefreshToken: true);
    try {
      await refreshFuture;
    } catch (e, stackTrace) {
      if (identical(_refreshTokenFuture, refreshFuture)) {
        _refreshTokenFuture = null;
      }
      if (error.requestOptions.path.startsWith('/api/')) {
        _updateLoadingState(config, false);
      }
      await _handleError(e, error.requestOptions, handler, true,
          stackTrace: stackTrace);
      return;
    }
    if (identical(_refreshTokenFuture, refreshFuture)) {
      _refreshTokenFuture = null;
    }
    await _retryRequest(error, handler);
  }

  Future<void> _retryRequestWithTimeout(
      DioException error, ErrorInterceptorHandler handler) async {
    var rng = Random();
    var timeout = Duration(milliseconds: 1000 + rng.nextInt(3000));
    await _retryRequest(error, handler, delay: timeout);
  }

  Future<void> _retryRequest(
      DioException error, ErrorInterceptorHandler handler,
      {Duration? delay}) async {
    if (delay != null) {
      await Future.delayed(delay);
    }
    var options = error.requestOptions;
    var extra = Map<String, dynamic>.from(options.extra);
    extra['isRetry'] = true;
    var response = await _dio.request<dynamic>(options.path,
        data: options.data,
        queryParameters: options.queryParameters,
        cancelToken: options.cancelToken,
        onReceiveProgress: options.onReceiveProgress,
        onSendProgress: options.onSendProgress,
        options: Options(
          method: options.method,
          sendTimeout: options.sendTimeout,
          receiveTimeout: options.receiveTimeout,
          extra: extra,
          headers: options.headers,
          responseType: options.responseType,
          contentType: options.contentType,
          validateStatus: options.validateStatus,
          receiveDataWhenStatusError: options.receiveDataWhenStatusError,
          followRedirects: options.followRedirects,
          maxRedirects: options.maxRedirects,
          requestEncoder: options.requestEncoder,
          responseDecoder: options.responseDecoder,
          listFormat: options.listFormat,
        ));
    handler.resolve(response);
  }

  Future<void> _handleError(Object error, RequestOptions requestOptions,
      ErrorInterceptorHandler handler, bool notify,
      {StackTrace? stackTrace}) async {
    var tbError = toThingsboardError(error, stackTrace);
    if (notify) {
      _onError(tbError);
    }
    handler.next(DioException(
      requestOptions: requestOptions,
      error: tbError,
      stackTrace: stackTrace ?? tbError.getStackTrace(),
      type: DioExceptionType.unknown,
    ));
  }

  InterceptorConfig _getInterceptorConfig(RequestOptions options) {
    return InterceptorConfig.fromExtra(options.extra);
  }

  bool _updateAuthorizationHeader(RequestOptions options) {
    var jwtToken = _tbClient.getJwtToken();
    if (jwtToken != null) {
      options.headers[_authHeaderName] = _authScheme + jwtToken;
      return true;
    } else {
      return false;
    }
  }

  bool _isInternalUrlPrefix(String url) {
    for (var prefix in _internalUrlPrefixes) {
      if (url.startsWith(prefix)) {
        return true;
      }
    }
    return false;
  }

  bool _isTokenBasedAuthEntryPoint(String url) {
    return url.startsWith('/api/') &&
        !url.startsWith(Constants.entryPoints['login']!) &&
        !url.startsWith(Constants.entryPoints['tokenRefresh']!) &&
        !url.startsWith(Constants.entryPoints['nonTokenBased']!);
  }

  void _updateLoadingState(InterceptorConfig config, bool isLoading) {
    if (!config.ignoreLoading) {
      if (isLoading) {
        _activeRequests++;
      } else {
        _activeRequests--;
      }
      if (_activeRequests == 1 && isLoading) {
        _loadStart();
      } else if (_activeRequests == 0) {
        _loadFinish();
      }
    }
  }
}
