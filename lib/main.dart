import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dowser/data.dart';
import 'package:flhooks/flhooks.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:stream_transform/stream_transform.dart';
import 'package:url_launcher/url_launcher.dart';

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

Position usePosition(
    [LocationOptions locationOptions = const LocationOptions(
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
      'https://untitled-7n0vxwvqdc4j.runkit.sh/?lng=${latLng.longitude}&lat=${latLng.latitude}');
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

LatLng _positionToLatLng(Position position) => LatLng(
      position.latitude,
      position.longitude,
    );

class AppConfig {
  final double defaultZoom;

  AppConfig({
    this.defaultZoom = 15.0,
  });
}

Geolocator _geolocator = Geolocator();

Stream<Position> _getPositionStream() =>
    _geolocator.getPositionStream(const LocationOptions(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    ));

void _showError(BuildContext context, error) {
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
    final appConfigProvider = Provider.value(
      value: AppConfig(
        defaultZoom: 15.00,
      ),
    );
    final positionStreamProvider = StreamProvider.value(
      value: _getPositionStream(),
      catchError: (context, error) {
        WidgetsBinding.instance.addPostFrameCallback((duration) {
          _showError(context, error);
        });
      },
    );
    final waterPointsProvider = StreamProvider<WaterPoints>.value(
      value: _getPositionStream()
          .transform(
            debounce(Duration(milliseconds: 300)),
          )
          .map(_positionToLatLng)
          .asyncMap(_fetchWaterPoints),
      catchError: (context, error) {
        WidgetsBinding.instance.addPostFrameCallback((duration) {
          _showError(context, error);
        });
      },
    );
    return MaterialApp(
      title: 'Dowser',
      theme: ThemeData(
        primaryColor: Colors.white,
      ),
      home: MultiProvider(
        providers: [
          appConfigProvider,
          positionStreamProvider,
          waterPointsProvider,
        ],
        child: HomePage(),
      ),
    );
  }
}

Marker _waterPointToMarker(
  WaterPoint waterPoint, {
  VoidCallback onTap,
  WaterPoint selected,
}) {
  final isSelected = selected?.id == waterPoint?.id;
  return Marker(
    markerId: MarkerId(waterPoint.id),
    position: LatLng(
      waterPoint.lat,
      waterPoint.lng,
    ),
    zIndex: isSelected ? 100 : 0,
    icon: isSelected
        ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure)
        : BitmapDescriptor.defaultMarker,
    onTap: onTap,
    consumeTapEvents: true,
  );
}

class HomePage extends HookWidget {
  HomePage() : super();

  @override
  Widget builder(BuildContext context) {
    final config = useProvider<AppConfig>();
    final position = useProvider<Position>();
    final cameraController = useState<GoogleMapController>(null);
    final selected = useState<WaterPoint>(null);
    useEffect(() {
      if (cameraController.value != null &&
          position != null &&
          selected.value == null) {
        cameraController.value.animateCamera(CameraUpdate.newLatLng(
          LatLng(
            position.latitude,
            position.longitude,
          ),
        ));
      }
    }, [position, cameraController.value, selected]);
    final markers = useProvider<WaterPoints>()?.list;
    Widget body = markers != null
        ? GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition:
                CameraPosition(target: LatLng(0, 0), zoom: config.defaultZoom),
            onMapCreated: (GoogleMapController controller) {
              cameraController.value = controller;
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            markers: markers
                ?.map((waterPoint) => _waterPointToMarker(waterPoint,
                        selected: selected.value, onTap: () {
                      selected.value = waterPoint;
                      cameraController.value.animateCamera(
                          CameraUpdate.newLatLng(
                              LatLng(waterPoint.lat, waterPoint.lng)));
                    }))
                ?.toSet(),
          )
        : Center(
            child: new CircularProgressIndicator(),
          );
    return Scaffold(
      appBar: AppBar(),
      bottomNavigationBar: BottomNavigationSection(
        child: selected.value != null
            ? WaterPointPreview(
                waterPoint: selected.value,
              )
            : null,
      ),
      body: body,
    );
  }
}

const MIN_HEIGHT = 20.0;
const MAX_HEIGHT_RATIO = 0.3;

class BottomNavigationSection extends HookWidget {
  final Widget child;

  BottomNavigationSection({
    this.child,
  });

  @override
  Widget builder(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          overflow: Overflow.clip,
          alignment: Alignment.bottomCenter,
          children: <Widget>[
            Container(
              height: child != null
                  ? max(
                      max(constraints.minHeight,
                          min(MIN_HEIGHT, constraints.maxHeight)),
                      constraints.maxHeight * MAX_HEIGHT_RATIO)
                  : max(constraints.minHeight, MIN_HEIGHT),
              decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black12,
                        offset: Offset(0, -1),
                        blurRadius: 8)
                  ],
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(15.0),
                    topRight: Radius.circular(15.0),
                  )),
              child: child,
            ),
          ],
        );
      },
    );
  }
}

_openMap(double latitude, double longitude) async {
  String googleUrl = 'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude';
  if (await canLaunch(googleUrl)) {
    await launch(googleUrl);
  } else {
    throw 'Could not open the map.';
  }
}

class WaterPointPreview extends StatelessWidget {
  final WaterPoint waterPoint;

  const WaterPointPreview({Key key, @required this.waterPoint})
      : assert(waterPoint != null),
        super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            title: Text(waterPoint.address),
            subtitle: Text('address'),
            trailing: Icon(
              Icons.directions,
              size: 46,
              color: Colors.blue[800],
            ),
            enabled: true,
            onLongPress: () => _openMap(waterPoint.lat, waterPoint.lng),
          ),
        ],
      ),
    );
  }
}
