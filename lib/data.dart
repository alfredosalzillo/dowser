class Distance {
  final double distanceEarthRadians;
  final String distance;
  final String unit;

  Distance({
    this.distanceEarthRadians,
    this.distance,
    this.unit,
  });
  
  factory Distance.fromJson(Map<String, dynamic> json) => Distance(
    distanceEarthRadians: json["distance_earth_radians"],
    distance: json["distance"],
    unit: json["km"],
  );
}

class WaterPoint {
  final String id;
  final String address;
  final String type;
  final double lat;
  final double lng;
  final Distance distance;

  WaterPoint({
    this.id,
    this.address,
    this.type,
    this.lat,
    this.lng,
    this.distance,
  });

  factory WaterPoint.fromJson(Map<String, dynamic> json) {
    return WaterPoint(
      id: json['id'],
      address: json['addres'],
      type: json['type'],
      lat: json['lat'],
      lng: json['lng'],
      distance: Distance.fromJson(json['distance']),
    );
  }
}

class ApiError extends Error {
  final int statusCode;
  final String error;
  final String message;

  ApiError({
    this.error = 'generic_error',
    this.message = 'A generic error occured.',
    this.statusCode = 500,
  });

  factory ApiError.fromJson(Map<String, dynamic> json, [int statusCode = 500]) {
    return ApiError(
        error: json['error'], message: json['message'], statusCode: statusCode);
  }

  @override
  String toString() => "ApiError(${this.error}): ${this.message}";
}
