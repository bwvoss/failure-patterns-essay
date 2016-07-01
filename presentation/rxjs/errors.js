var Rx = require('rx');
var source = Rx.Observable.of(1,2,3,4,5);

var observer = Rx.Observer.create(
    function (x) { console.log('onNext: %s', x); },
    function (e) { console.log('onError: %s', e); },
    function () { console.log('onCompleted'); });


source
  .map(function(s) { return s * 2 })
  .filter(function(s) { if(s == 4) {throw(new Error('woops!'))} })
  .subscribe(observer);
