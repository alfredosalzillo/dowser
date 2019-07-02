import 'package:flhooks/flhooks.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

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

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(title: 'Dowser'),
    );
  }
}

class MyHomePage extends HookWidget {
  MyHomePage({this.title}) : super();

  final String title;

  @override
  Widget builder(BuildContext context) {
    final counter = useState(0);
    final position = usePosition();
    return Scaffold(
      appBar: AppBar(
        title: Text(this.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'Current position ${position?.latitude}, ${position?.longitude}',
            ),
            Text(
              'You have pushed the button this many times:',
            ),
            Text(
              '${counter.value}',
              style: Theme.of(context).textTheme.display1,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => counter.value += 1,
        tooltip: 'Increment',
        child: Icon(Icons.add),
      ),
    );
  }
}
