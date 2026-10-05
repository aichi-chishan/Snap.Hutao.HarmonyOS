// SDK boundary only: the production @Concurrent body still runs. This is not a native threading test.
module.exports=function sdkDouble(state){
  let active;
  class Task{constructor(fn,...args){this.fn=fn;this.args=args;this.cancelled=false;}static isCanceled(){return active?.cancelled??false;}}
  const taskpool={Task,cancel(task){task.cancelled=true;state.workerCancels=(state.workerCancels??0)+1;},async execute(task){
    state.workerStarts=(state.workerStarts??0)+1;state.lastTask=task;
    if(state.failWorkerStart)throw Error('native executor unavailable');
    if(state.workerGate)await state.workerGate.promise;
    if(state.workerFailure)throw Error('native failed');
    active=task;state.inWorker=true;
    try{return state.workerWire??task.fn(...task.args);}finally{active=undefined;state.inWorker=false;}
  }};
  const fileIo={OpenMode:{READ_ONLY:1,READ_WRITE:2,TRUNC:4},openSync(){state.opens=(state.opens??0)+1;return {fd:1};},
    statSync(){state.statCalls=(state.statCalls??0)+1;return {size:state.statCalls>1&&state.afterSize!==undefined?state.afterSize:state.statSize??(state.bytes?.length??Buffer.byteLength(state.text??''))};},
    readSync(fd,buffer){new Uint8Array(buffer).set(state.bytes??Buffer.from(state.text??''));return state.shortRead?buffer.byteLength-1:buffer.byteLength;},
    closeSync(){state.closes=(state.closes??0)+1;if(state.closeError)throw Error(state.closeMessage??'close failed');},
    writeSync(fd,bytes){state.writeLengths.push(bytes.byteLength);state.writes.push(Buffer.from(bytes).toString('utf8'));return state.shortWrite?bytes.byteLength-1:bytes.byteLength;}};
  const util={TextDecoder:{create:(encoding,options)=>({decodeToString:bytes=>new TextDecoder(encoding,options).decode(bytes)})},TextEncoder:{create:()=>({encodeInto:text=>new Uint8Array(Buffer.from(text,'utf8'))})}};
  return {arkTS:{taskpool,util},files:{fileIo},globals:{setTimeout,clearTimeout,ArrayBuffer:class extends ArrayBuffer{constructor(size){(state.allocations??=[]).push(size);super(size);}}}};
};
