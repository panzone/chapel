config const n = 10;

class mink : ReduceScanOp {

  type eltType;
  const k : int;
  var v: [1..k] eltType = max(eltType);
  
  def accumulate(x: eltType)
  {
    if (x < v[1])
      {
        v[1] = x;
        for i in 2..k
          {
            if (v[i-1] < v[i])
              {
                v[i] <=> v[i-1];
              }
          }
      }
  }
  
  def combine(s: mink(eltType))
  {
    for i in 1..k
      {
        accumulate(s.v[i]);
      }
  }
  
  def generate()
  {
    var t = v;
    writeln("returning: ", t);
    return t;
  }
}

var A: [i in 1..n] int = i;
var minimums = mink(k=5) reduce A;
  

writeln("minimums is: ", minimums);
