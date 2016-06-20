var Rx = require('rx');
var source = Rx.Observable.from([1,2,3,4,5]);

var observer = Rx.Observer.create(
    function (x) { console.log('onNext: %s', x); },
    function (e) { console.log('onError: %s', e); },
    function () { console.log('onCompleted'); });


var subscription = source
  .map(function(s) { return s * 2 })
  .filter(function(s) { return notDefd })
  .subscribe(observer);
