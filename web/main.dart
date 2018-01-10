import 'dart:async';
import 'dart:collection';
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
  var input = () {
    var value = val.get();

    return Dom.input()
      ..key = "my-text-input"
      ..type = "text"
      ..value = value
      ..onChange = ((evt) => val.set(evt.target.value));
  };

  var app = (Observer()
    ..child = () => Dom.div()((Dom.img()..src = "https://media1.giphy.com/media/BoBOKNtlR8rTi/giphy.gif")(),
        title("Observable value is ${val.get()}"), input()()))();

  react_dom.render(app, document.getElementById("output"));
}

typedef void OnChange<T>(T newValue);

typedef Change<T> InterceptChange<T>(Change<T> incomingChange);

class Change<T> {
  T newValue;
  bool prevent = false;

  Change(this.newValue);
}

class Observable<T> {
  T _value;

  Observable(this._value);

  List<InterceptChange<T>> _interceptListeners = [];

  /// A synchronous event stream that receives an event whenever *any* observable's value is
  /// accessed with `observable.get()`.
  static var accessStreamSync = new StreamController<Observable<dynamic>>.broadcast(sync: true);

  /// An asynchronous event stream that receives an event whenever *any* observable's value is
  /// accessed with `observable.get()`.
  static var accessStreamAsync = new StreamController<Observable<dynamic>>.broadcast();

  /// A synchronous event stream that receives an event whenever the observable's value changes.
  ///
  /// Forced to synchronous because React state can become out of sync when the observable is used
  /// in a React component (for instance, updating a controlled input will force the cursor to the
  /// end of the line after every keypress).
  /// https://stackoverflow.com/a/28922465
  var onChangeSync = new StreamController<T>.broadcast(sync: true);

  /// An asynchronous event stream that receives an event whenever the observable's value changes. If
  /// you need to intercept and potentially change the new value, use the observable's `intercept` method.
  var onChangeAsync = new StreamController<T>.broadcast(sync: true);

  set(T value) {
    var change = _interceptListeners.fold(new Change<T>(value), (Change<T> state, InterceptChange<T> intercept) {
      // Freeze on the first interceptor to prevent a change
      return state.prevent ? state : intercept(state);
    });

    if (change.prevent) return;

    this._value = change.newValue;

    if (onChangeAsync.hasListener) {
      onChangeAsync.add(change.newValue);
    }

    if (onChangeSync.hasListener) {
      onChangeSync.add(change.newValue);
    }
  }

  T get() {
    if (accessStreamAsync.hasListener) {
      accessStreamAsync.add(this);
    }

    if (accessStreamSync.hasListener) {
      accessStreamSync.add(this);
    }

    return this._value;
  }

  intercept(InterceptChange<T> interceptor) => _interceptListeners.add(interceptor);
}

typedef ReactElement Render();

@Factory()
UiFactory<ObserverProps> Observer;

@Props()
class ObserverProps extends UiProps {
  Render child;
}

@State()
class ObserverState extends UiState {
  ReactElement currentChild;
}

@Component()
class ObserverComponent extends UiStatefulComponent<ObserverProps, ObserverState> {
  var observerSubscriptions = new HashMap<Observable<dynamic>, StreamSubscription<dynamic>>();

  ReactElement watchAndRenderStatic(Render renderChild, StreamController<Observable<dynamic>> watcher) {
    AccessWatcher.beginWatch(watcher);
    var child = renderChild();
    AccessWatcher.endWatch(watcher);

    return child;
  }

  ReactElement react() {
    // 1. Attach to the global access stream.
    // 2. Render the child.
    // 3. Disconnect from the access stream.
    // 4. Maintain a list of instance-specific observable streams.
    // 5. On next reaction, disconnect all of those observable subscriptions.
    // 6. GOTO 1.

    // Clear and cancel any instance observers from previous render cycles to prevent recursion
    observerSubscriptions
      ..forEach((_, sub) => sub.cancel())
      ..clear();

    var instanceWatcher = new StreamController<Observable<dynamic>>()
      ..stream.listen((obs) {
        // Check if the observer is already being tracked. If not, subscribe to its sync change stream and add it to the map of tracked observables.
        observerSubscriptions.putIfAbsent(
            obs, () => obs.onChangeSync.stream.listen((val) => this.setState(newState()..currentChild = react())));
      });
    var renderedChild = watchAndRenderStatic(this.props.child, instanceWatcher);

    // Close the stream as this instance is no longer interested in accessed observables.
    instanceWatcher.close();

    return renderedChild;
  }

  @override
  getInitialState() {
    return newState()..currentChild = react();
  }

  @override
  componentWillMount() {
    // BUG: We listen to the global stream for access to any observable then we subscribe to that
    // observable and redraw whenever it changes. This means we redraw when *any* observable changes,
    // not just one that was used in this observer.

    // INFO: previously I had attempted to subscribe to the access stream before rendering the child,
    // then add the accessed observables to the instance-specific list as they were accessed in the
    // child's render function, and finally remove the access stream subscription after child rendering
    // completed. THe problem is that in Dart streams are async and run in "microtasks" rather than
    // asynchronously. So when we wire up the global access stream listener and then shut it down after
    // rendering the child, none of those access events have been pushed to the stream yet.

    // SOLUTION: It's possible to create synchronous global streams where the event is dispatched.

    // SOLUTION: What if we use sync global stream, then make the Observer class itself listen to that
    // stream. Next we have each observer create its own stream, give it to the Observer class before
    // rendering the child. Because the global stream is sync, we can immediately post the accessed
    // observers to the instance stream and close it after rendering the child.

    super.componentWillMount();
  }

  @override
  componentWillUnmount() {
    // Clear all subscriptions to prevent accidentally attempted to react to observable changes.
    observerSubscriptions
      ..forEach((_, sub) => sub.cancel())
      ..clear();

    super.componentWillUnmount();
  }

  @override
  ReactElement render() {
    return this.state.currentChild;
  }
}

class AccessWatcher {
  static List<StreamController<Observable<dynamic>>> streams = [];

  static StreamSubscription<Observable<dynamic>> accessWatcher;

  static void beginWatch(StreamController<Observable<dynamic>> streamController) {
    // Create the access watcher subscription if necessary.
    // The access stream should only ever notify the *latest* listener
    // to be added to the list. Once that listener is done it gets removed
    // and the next latest listener starts listening again.
    streams.add(streamController);

    if (accessWatcher == null) {
      // Use Observable's synchronous access stream, so we'll immediately learn of which observables are used when
      // rendering the child. If it were async we wouldn't get any of the observables before the subscription is closed.
      accessWatcher = Observable.accessStreamSync.stream.listen((obs) {
        if (streams.isNotEmpty) {
          streams.last.add(obs);
        }
      });
    }
  }

  static void endWatch(StreamController<Observable<dynamic>> streamController) {
    streams.removeWhere((s) => s.hashCode == streamController.hashCode);

    if (streams.isEmpty) {
      accessWatcher.cancel();
      accessWatcher = null;
    }
  }
}
