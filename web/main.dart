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

  val.observe((newValue) {
    print("Value changed to $newValue");
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

  List<OnChange<T>> _changeListeners = [];

  List<InterceptChange<T>> _interceptListeners = [];

  Observable(this._value);

  static List<AccessWatcher> _globalAccessWatchers = [];

  static void addGlobalAccessWatcher(AccessWatcher watcher) => _globalAccessWatchers.add(watcher);

  static void removeGlobalAccessWatcher(AccessWatcher watcher) => _globalAccessWatchers.remove(watcher);

  set(T value) {
    var change = _interceptListeners.fold(new Change<T>(value), (Change<T> state, InterceptChange<T> intercept) {
      // Freeze on the first interceptor to prevent a change
      return state.prevent ? state : intercept(state);
    });

    if (change.prevent) return;

    this._value = change.newValue;
    _changeListeners.forEach((listener) => listener(change.newValue));
  }

  get() {
    for (var watcher in _globalAccessWatchers) watcher(this);

    return this._value;
  }

  observe(OnChange<T> onChange) => _changeListeners.add(onChange);

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

  /// A single instance of a global access watcher. Should never be changed after instantiation.
  static AccessWatcher _globalAccessWatcher = null;

  /// A signel instance of a global access watcher. Should change and reset according to which observer is rendering.
  static AccessWatcher _onGlobalAccess = null;

  static RenderAndObserveResult renderAndObserve(Render render) {
    List<Observable<dynamic>> observables = [];

    if (_globalAccessWatcher == null) {
      _globalAccessWatcher = (observable) {
        if (_onGlobalAccess != null) {
          _onGlobalAccess(observable);
        }
      };

      Observable.addGlobalAccessWatcher(_globalAccessWatcher);
    }

    var oldGlobalAccess = _onGlobalAccess;
    _onGlobalAccess = observables.add;

    var result = render();

    _onGlobalAccess = oldGlobalAccess;

    return new RenderAndObserveResult(result, observables);
  }

  @override
  componentWillMount() {
    // Dart streams would probably be perfect here, but since they're async it can't be used in the render process.
    List<Observable<dynamic>> observables = [];

    void rerender() {
      var renderResult = ObserverComponent.renderAndObserve(this.props.child);
      this.renderedChild = renderResult.result;
      observables = renderResult.observables;

      // There's probably a bug here that will cause these functions to continue to be called and redraw the Observer.
      // They need to be disposed in some way so they'll never be called after they're no longer used in the observer.
      // Best way to do that is making the Observable.observe function return a class that can be used to call .dispose.
      observables.forEach((observable) => observable.observe((newValue) => rerender()));

      if (this.hasMounted) {
        this.redraw();
      }
    }

    rerender();

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
