import Foundation
import CoreBluetooth
let LOG = FileManager.default.currentDirectoryPath + "/ble_test.log"
try? "".write(toFile:LOG,atomically:true,encoding:.utf8)
func log(_ s:String){if let h=FileHandle(forWritingAtPath:LOG){h.seekToEndOfFile();h.write((s+"\n").data(using:.utf8)!);try? h.close()}}
func hexs(_ b:ArraySlice<UInt8>)->String{b.map{String(format:"%02x",$0)}.joined(separator:" ")}
let SVC=CBUUID(string:"52401523-F97C-7F90-0E7F-6C6F4E36DB1C")
let C1=CBUUID(string:"52401524-F97C-7F90-0E7F-6C6F4E36DB1C")
let C2=CBUUID(string:"52401525-F97C-7F90-0E7F-6C6F4E36DB1C")
let C3=CBUUID(string:"52401526-F97C-7F90-0E7F-6C6F4E36DB1C")
// (label, class, id, args) — args go in payload; empty -> 1 dummy byte
let T:[(String,UInt8,UInt8,[UInt8])]=[
 ("00:81 device   ",0x00,0x81,[]),("05:81 profiles ",0x05,0x81,[]),
 ("0f:82 lighting ",0x0f,0x82,[1,0]),("0b:85 sensor   ",0x0b,0x85,[1]),
 ("10:81 class0x10",0x10,0x81,[1]),("15:80 hapticore",0x15,0x80,[1]),
 ("04:85 DPI      ",0x04,0x85,[1]),("02:8e buttons  ",0x02,0x8e,[1,0,0]),
 ("06:89 macros   ",0x06,0x89,[1,0,0,0,0,0]),("07:80 power    ",0x07,0x80,[])]
final class BLE:NSObject,CBCentralManagerDelegate,CBPeripheralDelegate{
  var cm:CBCentralManager!;var p:CBPeripheral?;var w:CBCharacteristic?;var i=0;var nr=0;var got=false;var tr=0;var phase=0
  override init(){super.init();cm=CBCentralManager(delegate:self,queue:nil)}
  func centralManagerDidUpdateState(_ c:CBCentralManager){if c.state == .poweredOn{grab()}}
  func grab(){let ps=cm.retrieveConnectedPeripherals(withServices:[CBUUID(string:"180F")])
    if let m=ps.first(where:{($0.name ?? "").uppercased().contains("BSK")}){p=m;m.delegate=self;cm.connect(m)}
    else{tr+=1;if tr<10{DispatchQueue.main.asyncAfter(deadline:.now()+0.5){self.grab()}}else{log("no mouse");exit(1)}}}
  func centralManager(_ c:CBCentralManager,didConnect pp:CBPeripheral){pp.discoverServices([SVC])}
  func peripheral(_ pp:CBPeripheral,didDiscoverServices e:Error?){for s in pp.services ?? [] where s.uuid==SVC{pp.discoverCharacteristics([C1,C2,C3],for:s)}}
  func peripheral(_ pp:CBPeripheral,didDiscoverCharacteristicsFor s:CBService,error e:Error?){for ch in s.characteristics ?? []{if ch.uuid==C1{w=ch};if ch.uuid==C2||ch.uuid==C3{pp.setNotifyValue(true,for:ch)}}}
  func peripheral(_ pp:CBPeripheral,didUpdateNotificationStateFor ch:CBCharacteristic,error e:Error?){nr+=1;if nr==2{log("=== BLE class coverage (status 2=OK, 5=UNSUPPORTED) ===");send()}}
  func send(){guard i<T.count,let w=w,let p=p else{log("=== done ===");exit(0)}
    got=false;phase=0;let t=T[i];let args=t.3.isEmpty ? [UInt8(0)] : t.3;let n=args.count
    let hdr:[UInt8]=[0,UInt8(n & 0xff),UInt8(n>>8),0,t.1,t.2,0,0]
    p.writeValue(Data(hdr),for:w,type:.withResponse)
    DispatchQueue.main.asyncAfter(deadline:.now()+0.08){p.writeValue(Data(args),for:w,type:.withResponse)}
    DispatchQueue.main.asyncAfter(deadline:.now()+2.0){if !self.got{log(t.0+" -> NO RESPONSE")};self.i+=1;self.send()}}
  func peripheral(_ pp:CBPeripheral,didUpdateValueFor ch:CBCharacteristic,error e:Error?){
    guard i<T.count,let d=ch.value else{return};let b=[UInt8](d)
    if phase==0 { // response header: status at [7], len at [1..2]
      let st=b.count>=8 ? b[7]:255; let lbl=st==2 ? "OK":(st==5 ? "UNSUPPORTED":"st\(st)")
      log(T[i].0+" -> status=\(st) [\(lbl)]"); phase=1; got=true
    } else {
      log("      data: "+hexs(b.prefix(16)))
    }}
}
let keep=BLE();RunLoop.main.run(until:Date().addingTimeInterval(28))
