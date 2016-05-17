var Rx = require('rx');
var array = Rx.Observable.from([1,2,3,4,5]);
// var error = Rx.Observable.throw(new Error('woops'));
var source = Rx.Observable.merge(array);

var observer = Rx.Observer.create(
    function (x) { console.log('onNext: %s', x); },
    function (e) { console.log('onError: %s', e); },
    function () { console.log('onCompleted'); });


var subscription = source
  .map(function(s) { return s * 2 })
  .subscribe(observer);
