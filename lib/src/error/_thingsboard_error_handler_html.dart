import 'dart:convert';
import 'dart:html';
import 'package:dio/dio.dart';

import 'thingsboard_error.dart';

int httpStatusToThingsboardErrorCode(int status) {
  switch (status) {
    case HttpStatus.unauthorized:
      return ThingsBoardErrorCode.authentication;
    case HttpStatus.forbidden:
      return ThingsBoardErrorCode.permissionDenied;
    case HttpStatus.badRequest:
      return ThingsBoardErrorCode.badRequestParams;
    case HttpStatus.notFound:
      return ThingsBoardErrorCode.itemNotFound;
    case HttpStatus.tooManyRequests:
      return ThingsBoardErrorCode.tooManyRequests;
    case HttpStatus.internalServerError:
      return ThingsBoardErrorCode.general;
    default:
      return ThingsBoardErrorCode.general;
  }
}

ThingsboardError toThingsboardError(error, [StackTrace? stackTrace]) {
  ThingsboardError? tbError;
  if (error is DioException) {
    final response = error.response;
    if (response != null && response.data != null) {
      var data = response.data;
      if (data is ThingsboardError) {
        tbError = data;
      } else if (data is Map<String, dynamic>) {
        tbError = ThingsboardError.fromJson(data);
      } else if (data is String) {
        try {
          tbError = ThingsboardError.fromJson(jsonDecode(data));
        } catch (_) {
          var message = data.trim().isEmpty ? data : data.trim();
          if (message.isNotEmpty) {
            tbError = ThingsboardError(
                error: error,
                message: message,
                errorCode: ThingsBoardErrorCode.general,
                status: response.statusCode);
          }
        }
      }
    } else if (error.error != null) {
      var originalError = error.error;
      if (originalError is ThingsboardError) {
        tbError = originalError;
      } /* else if (error.error is SocketException) {
        tbError = ThingsboardError(
            error: error,
            message: 'Unable to connect',
            errorCode: ThingsBoardErrorCode.general);
      }*/
      else {
        tbError = ThingsboardError(
            error: error,
            message: originalError.toString(),
            errorCode: ThingsBoardErrorCode.general,
            status: response?.statusCode);
      }
    }
    if (tbError == null && response != null && response.statusCode != null) {
      var httpStatus = response.statusCode!;
      var statusMessage =
          response.statusMessage != null && response.statusMessage!.isNotEmpty
              ? response.statusMessage!
              : 'Unknown';
      var message = '${httpStatus.toString()}: $statusMessage';
      tbError = ThingsboardError(
          error: error,
          message: message,
          errorCode: httpStatusToThingsboardErrorCode(httpStatus),
          status: httpStatus);
    }
  } else if (error is ThingsboardError) {
    tbError = error;
  }
  tbError ??= ThingsboardError(
      error: error,
      message: error.toString(),
      errorCode: ThingsBoardErrorCode.general);

  StackTrace? errorStackTrace;
  if (tbError.error is Error) {
    errorStackTrace = tbError.error.stackTrace;
  }

  tbError.stackTrace = stackTrace ??
      tbError.getStackTrace() ??
      errorStackTrace ??
      StackTrace.current;

  return tbError;
}
