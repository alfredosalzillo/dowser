import 'dart:async';
import 'dart:convert';

import 'package:dowser/data.dart';
import 'package:flhooks/flhooks.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

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
  final dynamic error;

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

T useProvider<T>() {
  return Provider.of<T>(useContext());
}

Position usePosition([LocationOptions locationOptions = const LocationOptions(
    accuracy: LocationAccuracy.high, distanceFilter: 10)]) {
  final geolocator = useMemo(() => Geolocator(), []);
  return useStreamValue(
          () => geolocator.getPositionStream(locationOptions), []);
}

class WaterPoints {
  final List<WaterPoint> list;

  WaterPoints({this.list});
}

Future<WaterPoints> _fetchWaterPoints(LatLng latLng) async {
  final response = await http.get(
      'https://untitled-7n0vxwvqdc4j.runkit.sh/?lng=${latLng
          .longitude}&lat=${latLng.latitude}');
  debugPrint(response.statusCode.toString());
  final data = json.decode(response.body);
  if (response.statusCode == 200) {
    return WaterPoints(
        list: (data as List)
            .map((json) => WaterPoint.fromJson(json))
            .toList(growable: false));
  }
  throw ApiError.fromJson(json.decode(response.body), response.statusCode);
}

class AppConfig {
  final double defaultZoom;

  AppConfig({
    this.defaultZoom = 15.0,
  });
}

Stream<Position> _getPositionStream(BuildContext context) =>
    Geolocator().getPositionStream(const LocationOptions(
        accuracy: LocationAccuracy.high, distanceFilter: 10));

void _showDialog(BuildContext context, error) {
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
            child: new Text("Retry"),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      );
    },
  );
}

class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dowser',
      theme: ThemeData(
        primaryColor: Colors.white,
      ),
      home: MultiProvider(
        providers: [
          Provider.value(
            value: AppConfig(
              defaultZoom: 15.00,
            ),
          ),
          StreamProvider(
            builder: _getPositionStream,
          ),
        ],
        child: Consumer<Position>(
          child: HomePage(),
          builder: (context, position, child) {
            debugPrint(position.toString());
            return FutureProvider<WaterPoints>.value(
              child: child,
              value: position != null
                  ? _fetchWaterPoints(
                  LatLng(position.latitude, position.longitude))
                  : Future.value(null),
              catchError: (context, error) {
                _showDialog(context, error);
                return null;
              },
            );
          },
        ),
      ),
    );
  }
}

Marker _waterPointToMarker(WaterPoint waterPoint) =>
    Marker(
      markerId: MarkerId(waterPoint.id),
      position: LatLng(
        waterPoint.lat,
        waterPoint.lng,
      ),
      infoWindow: InfoWindow(title: waterPoint.address),
    );

class HomePage extends HookWidget {
  HomePage() : super();

  @override
  Widget builder(BuildContext context) {
    final config = useProvider<AppConfig>();
    final position = useProvider<Position>();
    final cameraController = useState<GoogleMapController>(null);
    final zoom = useState(config.defaultZoom);
    final firstLoad = useState(true);
    useEffect(() {
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
    final markers = useProvider<WaterPoints>()?.list;
    Widget body;
    if (markers != null)
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
        markers: markers?.map(_waterPointToMarker)?.toSet(),
      );
    else
      body = Center(
        child: new CircularProgressIndicator(),
      );
    return Scaffold(
      appBar: AppBar(),
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
}
