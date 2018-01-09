import 'dart:async';
import 'dart:html';
import 'package:react/react_dom.dart' as react_dom;
import 'package:over_react/over_react.dart';

void main() {
  // Initialize React within our Dart app
  setClientConfiguration();

  var val = new Observable("test");

  val.intercept((change) {
    return change;
  });

  // NOTICE: It's VERY important to only get your observable values INSIDE the Observer's render function.
  var title = (Dom.h1()..key = "title");
  var input = () => Dom.input()
    ..type = "text"
    ..value = val.get()
    ..onChange = ((evt) => val.set(evt.target.value));

  var app = (Observer()..child = () => Dom.div()(title("Observable value is ${val.get()}"), input()()))();

  react_dom.render(app, document.getElementById("output"));
}

typedef void OnChange<T>(T newValue);

typedef Change<T> InterceptChange<T>(Change<T> incomingChange);

typedef void AccessWatcher(Observable<dynamic> onAccess);

class Change<T> {
  T newValue;
  bool prevent = false;

  Change(this.newValue);
}

class Observable<T> {
  T _value;

  // List<OnChange<T>> _changeListeners = [];

  List<InterceptChange<T>> _interceptListeners = [];

  Observable(this._value);

  static SynchronousStreamController<Observable<dynamic>> accessStream = new StreamController.broadcast(sync: true);

  StreamController<T> onChange = new StreamController.broadcast();

  set(T value) {
    var change = _interceptListeners.fold(new Change<T>(value), (Change<T> state, InterceptChange<T> intercept) {
      // Freeze on the first interceptor to prevent a change
      return state.prevent ? state : intercept(state);
    });

    if (change.prevent) return;

    this._value = change.newValue;
    onChange.add(change.newValue);
  }

  get() {
    if (accessStream.hasListener) {
      accessStream.add(this);
    }

    return this._value;
  }

  intercept(InterceptChange<T> interceptor) => _interceptListeners.add(interceptor);
}

ReactElement statelessFunc() {
  return (Dom.div()..className = "Hello world!!")("Hello world, this was built from a stateless boi");
}

typedef ReactElement Render();

@Factory()
UiFactory<ObserverProps> Observer;

@Props()
class ObserverProps extends UiProps {
  Render child;
}

class RenderAndObserveResult {
  List<Observable<dynamic>> observables = [];
  ReactElement result;

  RenderAndObserveResult(this.result, this.observables);
}

@Component()
class ObserverComponent extends UiComponent<ObserverProps> {
  ReactElement renderedChild;

  bool hasMounted = false;

  /// A single instance of a global access watcher. Should change and reset according to which observer is rendering.
  static AccessWatcher _onGlobalAccess = null;

  // static RenderAndObserveResult renderAndObserve(Render render) {
  //   List<Observable<dynamic>> observables = [];

  //   if (_globalAccessWatcher == null) {
  //     print("Creating global access watcher");

  //     _globalAccessWatcher = (observable) {
  //       if (_onGlobalAccess != null) {
  //         _onGlobalAccess(observable);
  //       }
  //     };

  //     // A list of instance-specific streams on each observable. When the observer starts listening it adds its stream
  //     // to the list. When its done it calls close on the stream and removes it? These streams can actually replace the
  //     // custom 'onChange' methods.

  //     Observable.accessStream.stream.listen((obs) {
  //       print("Observable accessed");
  //       obs.onChange.stream.listen((_) {});
  //     });
  //   }

  //   var oldGlobalAccess = _onGlobalAccess;
  //   _onGlobalAccess = observables.add;

  //   var result = render();

  //   _onGlobalAccess = oldGlobalAccess;

  //   return new RenderAndObserveResult(result, observables);
  // }

  List<StreamSubscription<dynamic>> instanceObservers = [];

  @override
  componentWillMount() {
    void watchAndRender() {
      // Clear and cancel any instance observers from previous render cycles to prevent recursion
      instanceObservers
        ..forEach((sub) => sub.cancel())
        ..clear();

      this.renderedChild = this.props.child();

      if (this.hasMounted) {
        this.redraw();
      }
    }

    // BUG: We listen to the global stream for access to any observable then we subscribe to that
    // observable and redraw whenever it changes. This means we redraw when *any* observable changes,
    // not just one that was used in this observer.

    // INFO: previously I had attempted to subscribe to the access stream before rendering the child,
    // then add the accessed observables to the instance-specific list as they were accessed in the
    // child's render function, and finally remove the access stream subscription after child rendering
    // completed. THe problem is that in Dart streams are async and run in "microtasks" rather than
    // asynchronously. So when we wire up the global access stream listener and then shut it down after
    // rendering the child, none of those access events have been pushed to the stream yet.

    // SOLUTION: It's possible to create synchronous global streams where the event is dispatched
    // immediately, though it's technically an antipattern.

    Observable.accessStream.stream.listen((obs) {
      print("Accessed observable with hashcode ${obs.hashCode}");
      // Add observable subscription to instance-specific list
      instanceObservers.add(obs.onChange.stream.listen((val) => watchAndRender()));
    }, cancelOnError: false);

    // 1. Attach to the global access stream.
    // 2. Render the child.
    // 3. Disconnect from the access stream.
    // 4. Maintain a list of instance-specific observable streams.
    // 5. On next redraw, disconnect all of those observable subscriptions.
    // 6. GOTO 1.

    watchAndRender();
    this.hasMounted = true;

    super.componentWillMount();
  }

  @override
  componentWillUnmount() {
    super.componentWillUnmount();
  }

  @override
  ReactElement render() {
    return this.renderedChild;
  }
}
