import 'dart:async';
import 'dart:convert';

import 'package:flhooks/flhooks.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

void main() => runApp(MyApp());

T useStream<T>(Stream<T> Function() fn, List<dynamic> store) {
  final state = useState<T>(null);
  useEffect(() {
    final subscription = fn().listen((data) {
      state.value = data;
    });
    return () => subscription.cancel();
  }, store);
  return state.value;
}

T useAsync<T>(Future<T> Function() fn, List<dynamic> store) {
  return useStream(() => fn().asStream(), store);
}

Position usePosition(
    [LocationOptions locationOptions = const LocationOptions(
        accuracy: LocationAccuracy.high, distanceFilter: 0)]) {
  final geolocator = useMemo(() => Geolocator(), []);
  return useStream(() => geolocator.getPositionStream(locationOptions), []);
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

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dowser',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: AppConfig(
        defaultZoom: 15.0,
        child: HomePage(title: 'Dowser'),
      ),
    );
  }
}

class HomePage extends HookWidget {
  HomePage({this.title}) : super();

  final String title;

  @override
  Widget builder(BuildContext context) {
    final AppConfig config = AppConfig.of(context);
    final position = usePosition();
    final _controller = useMemo(() => Completer<GoogleMapController>(), []);
    final cameraController = useAsync(() => _controller.future, []);
    final zoom = useState(config.defaultZoom);
    useEffect(() {
      if (cameraController != null && position != null) {
        cameraController.animateCamera(CameraUpdate.newLatLngZoom(
            LatLng(
              position.latitude,
              position.longitude,
            ),
            zoom.value));
      }
    }, [position?.longitude, position?.latitude, cameraController]);
    final markers = useStream<List>(
        () => position == null
            ? Stream.empty()
            : Geolocator()
                .getPositionStream(
                  LocationOptions(
                    accuracy: LocationAccuracy.high,
                    distanceFilter: 0,
                  ),
                )
                .asyncMap((position) => http.get(
                    'https://untitled-7n0vxwvqdc4j.runkit.sh/?lng=${position.longitude}&lat=${position.latitude}'))
                .map((response) => json.decode(response.body) as List),
        [position?.longitude, position?.latitude]);
    return Scaffold(
      appBar: AppBar(
        title: Text(this.title),
      ),
      body: GoogleMap(
        mapType: MapType.normal,
        initialCameraPosition: CameraPosition(target: LatLng(0, 0)),
        onMapCreated: (GoogleMapController controller) {
          _controller.complete(controller);
        },
        onCameraMove: (cameraPosition) {
          zoom.value = cameraPosition.zoom;
        },
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        markers: [
          if (markers != null)
            ...markers.map((json) => Marker(
                  markerId: MarkerId(json['id']),
                  position: LatLng(
                      double.parse(json['lat']), double.parse(json['lng'])),
                )),
        ].toSet(),
      ),
    );
  }
}
