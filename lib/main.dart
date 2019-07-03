import 'dart:async';
import 'dart:convert';

import 'package:dowser/data.dart';
import 'package:flhooks/flhooks.dart';
import 'package:flhooks/flhooks.dart' as prefix0;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

void main() => runApp(App());

T useStreamValue<T>(Stream<T> Function() fn, List<dynamic> store) {
  final state = useState<T>(null);
  useEffect(() {
    final subscription = fn().listen((data) {
      state.value = data;
    });
    return () => subscription.cancel();
  }, store);
  return state.value;
}

T useAsyncValue<T>(Future<T> Function() fn, List<dynamic> store) {
  return useStreamValue(() => fn().asStream(), store);
}

enum AsyncRequestStatus {
  none,
  loading,
  error,
  complete,
}

class AsyncController<T> {
  final AsyncRequestStatus status;
  final T value;
  final Error error;

  AsyncController({
    this.status = AsyncRequestStatus.none,
    this.value,
    this.error,
  });
}

AsyncController<T> useAsync<T>(Future<T> Function() fn, List<dynamic> store) {
  final status = useState(AsyncRequestStatus.none);
  final error = useState<Error>(null);
  final value = useState<T>(null);
  final future = useMemo(fn, store);
  useEffect(() {
    status.value = AsyncRequestStatus.loading;
    if (future != null) {
      future.catchError((e) {
        status.value = AsyncRequestStatus.error;
        error.value = e;
      }).then((v) {
        status.value = AsyncRequestStatus.complete;
        value.value = v;
      });
    }
  }, [future]);
  return AsyncController(
    status: status.value,
    value: value.value,
    error: error.value,
  );
}

Position usePosition(
    [LocationOptions locationOptions = const LocationOptions(
        accuracy: LocationAccuracy.high, distanceFilter: 10)]) {
  final geolocator = useMemo(() => Geolocator(), []);
  return useStreamValue(
      () => geolocator.getPositionStream(locationOptions), []);
}

Future<List<WaterPoint>> fetchWaterPoints(LatLng latLng) async {
  final response = await http.get(
      'https://untitled-7n0vxwvqdc4j.runkit.sh/?lng=${latLng.longitude}&lat=${latLng.latitude}');
  debugPrint(response.statusCode.toString());
  final data = json.decode(response.body);
  if (response.statusCode == 200) {
    return (data as List)
        .map((json) => WaterPoint.fromJson(json))
        .toList(growable: false);
  }
  throw ApiError.fromJson(json.decode(response.body), response.statusCode);
}

class AppConfig extends InheritedWidget {
  final double defaultZoom;

  AppConfig({
    this.defaultZoom = 15.0,
    key,
    child,
  }) : super(key: key, child: child);

  @override
  bool updateShouldNotify(InheritedWidget oldWidget) {
    return false;
  }

  static AppConfig of(BuildContext context) {
    return context.inheritFromWidgetOfExactType(AppConfig);
  }
}

class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dowser',
      theme: ThemeData(
        primaryColor: Colors.white,
      ),
      home: AppConfig(
        defaultZoom: 15.0,
        child: HomePage(title: 'Dowser'),
      ),
    );
  }
}

Marker _waterPointToMarker(WaterPoint waterPoint) => Marker(
      markerId: MarkerId(waterPoint.id),
      position: LatLng(
        waterPoint.lat,
        waterPoint.lng,
      ),
      infoWindow: InfoWindow(title: waterPoint.address),
    );

class HomePage extends HookWidget {
  HomePage({this.title}) : super();

  final String title;

  @override
  Widget builder(BuildContext context) {
    final AppConfig config = AppConfig.of(context);
    final position = usePosition();
    final cameraController = useState<GoogleMapController>(null);
    final zoom = useState(config.defaultZoom);
    prefix0.useEffect(() {
      zoom.value = config.defaultZoom;
    }, [cameraController.value]);
    useEffect(() {
      if (cameraController.value != null && position != null) {
        cameraController.value.animateCamera(CameraUpdate.newLatLngZoom(
            LatLng(
              position.latitude,
              position.longitude,
            ),
            zoom.value));
      }
    }, [position, cameraController.value]);
    final markers = useAsync<List<WaterPoint>>(() async {
      return position != null
          ? fetchWaterPoints(
              LatLng(
                position.latitude,
                position.longitude,
              ),
            )
          : null;
    }, [position]);
    Widget body;
    if (markers.status == AsyncRequestStatus.complete && markers.value != null)
      body = GoogleMap(
        mapType: MapType.normal,
        initialCameraPosition: CameraPosition(target: LatLng(0, 0)),
        onMapCreated: (GoogleMapController controller) {
          cameraController.value = controller;
        },
        onCameraMove: (cameraPosition) {
          zoom.value = cameraPosition.zoom;
        },
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        markers: markers.value?.map(_waterPointToMarker)?.toSet(),
      );
    if (markers.status == AsyncRequestStatus.loading)
      body = Center(
        child: new CircularProgressIndicator(),
      );
    if (markers.status == AsyncRequestStatus.error)
      _showDialog(context, markers.error);
    return Scaffold(
      appBar: AppBar(
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            title: Text('Home'),
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.business),
            title: Text('Business'),
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.school),
            title: Text('School'),
          ),
        ],
        currentIndex: 0,
        selectedItemColor: Colors.blue[800],
      ),
      body: body,
    );
  }

  void _showDialog(BuildContext context, ApiError error) {
    // flutter defined function
    showDialog(
      context: context,
      builder: (BuildContext context) {
        // return object of type Dialog
        return AlertDialog(
          title: new Text("Error"),
          content: new Text("An error occured: ${error.toString()}"),
          actions: <Widget>[
            // usually buttons at the bottom of the dialog
            new FlatButton(
              child: new Text("Reload"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}
