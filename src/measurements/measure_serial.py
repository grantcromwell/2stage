#!/usr/bin/env python3
"""Board measurement client; CRC validates all scoring inputs/results and bulk data."""
import argparse, json, math, os, select, statistics, struct, termios, time, zlib
from pathlib import Path

class Serial:
    def __init__(self,path,baud=115200):
        self.fd=os.open(path,os.O_RDWR|os.O_NOCTTY|os.O_NONBLOCK)
        self.rate(baud)
    def rate(self,baud):
        a=termios.tcgetattr(self.fd)
        a[0]=0;a[1]=0;a[2]=termios.CS8|termios.CLOCAL|termios.CREAD;a[3]=0
        a[4]=a[5]=getattr(termios,'B'+str(baud));a[6][termios.VMIN]=0;a[6][termios.VTIME]=0
        termios.tcsetattr(self.fd,termios.TCSANOW,a)
    def write(self,data,timeout=30):
        deadline=time.monotonic()+timeout;view=memoryview(data)
        while view:
            left=deadline-time.monotonic()
            if left<=0 or not select.select([], [self.fd], [], left)[1]: raise TimeoutError('serial write')
            try: n=os.write(self.fd,view);view=view[n:]
            except BlockingIOError: pass
    def read(self,n,timeout=30):
        deadline=time.monotonic()+timeout;data=bytearray()
        while len(data)<n:
            left=deadline-time.monotonic()
            if left<=0 or not select.select([self.fd],[],[],left)[0]: raise TimeoutError(f'serial read {len(data)}/{n}')
            try: data+=os.read(self.fd,n-len(data))
            except BlockingIOError: pass
        return bytes(data)
    def close(self):os.close(self.fd)

def summary(values):
    v=sorted(values)
    return dict(samples=len(v),mean=statistics.mean(v),p50=statistics.median(v),p95=v[math.ceil(.95*len(v))-1],minimum=v[0],maximum=v[-1])
def vectors(path):
    it=iter(Path(path).read_text().split())
    for _ in range(80):
        n,sat,err,q=(int(next(it),16) for _ in range(4))
        a=[int(next(it),16) for _ in range(576)]
        x=[int(next(it),16) for _ in range(24)]
        y=[int(next(it),16) for _ in range(24)]
        yield n,sat,err,q,a,x,y

def score(link,case):
    n,sat,err,q,a,x,y=case
    payload=struct.pack('<601I',n,*a,*x)
    request=b'S'+payload+struct.pack('<I',zlib.crc32(payload))
    start=time.perf_counter_ns();link.write(request);raw=link.read(136);elapsed=time.perf_counter_ns()-start
    assert zlib.crc32(raw[:-4])==struct.unpack('<I',raw[-4:])[0], 'response CRC'
    words=struct.unpack('<34I',raw)
    assert words[0]==0x31444853, words[:7]
    assert not(words[1]&0xc0000000),f'transport/IRQ timeout {words[:7]}'
    assert bool(words[1]&8)==bool(err) and bool(words[1]&16)==bool(sat) and words[1]&4, words[:7]
    assert list(words[7:31])==y,'direction mismatch'
    assert words[31]|(words[32]<<32)==q,'quadratic mismatch'
    assert words[2]==(25 if err else n*n+5*n+29),words[:7]
    return elapsed,words

def main():
    p=argparse.ArgumentParser();p.add_argument('--port',default='/dev/ttyACM0');p.add_argument('--ping',action='store_true');p.add_argument('--output',default='hardware_results.json');p.add_argument('--initial-baud',type=int,default=115200);p.add_argument('--rates',default='115200');p.add_argument('--skip-parity',action='store_true');a=p.parse_args()
    link=Serial(a.port,a.initial_baud)
    try:
        termios.tcflush(link.fd,termios.TCIFLUSH)
        link.write(b'P');hello=struct.unpack('<4I',link.read(16,5))
        assert hello[:2]==(0x314e4542,0x53484431),hello
        print('Board handshake:',hello,flush=True)
        if a.ping:return
        root=Path(__file__).resolve().parent
        cases=list(vectors(root/'testdata/shadow_vectors.txt'))
        result={'platform':'ZedBoard XC7Z020; bare-metal OCM firmware, CPU0 IRQ61', 'timer_hz':hello[2], 'configured_fclk_hz':hello[3], 'uart':{},'source':'live hardware, CRC/result verified'}
        rate=a.initial_baud
        
        if not a.skip_parity:
            for i,case in enumerate(cases):
                _,words=score(link,case)
                if i%10==0:print('Silicon parity',i+1,'/ 80',flush=True)
            result['silicon_parity_cases']=80
        else:
            result['silicon_parity_cases']='skipped in this run'
        case=cases[24]
        for baud in [int(value) for value in a.rates.split(',') if value]:
            if rate!=baud:
                link.write(b'V'+struct.pack('<I',baud));assert struct.unpack('<I',link.read(4))[0]==baud
                time.sleep(.05);link.rate(baud);rate=baud
                link.write(b'P');assert struct.unpack('<4I',link.read(16,5))==hello
            bulk_n=16384;payload=bytes((i*29+7)&255 for i in range(bulk_n));upload=[];download=[];board_rx=[]
            for _ in range(3):
                start=time.perf_counter_ns();link.write(b'U'+struct.pack('<I',bulk_n)+payload)
                magic,crc,ticks=struct.unpack('<3I',link.read(12));elapsed=(time.perf_counter_ns()-start)/1e9
                assert magic==0x314c5055 and crc==zlib.crc32(payload)
                upload.append(bulk_n/elapsed);board_rx.append(bulk_n/(ticks/hello[2]))
                start=time.perf_counter_ns();link.write(b'D'+struct.pack('<I',bulk_n));raw=link.read(bulk_n+8)
                elapsed=(time.perf_counter_ns()-start)/1e9
                assert raw[:4]==struct.pack('<I',0x314e5744) and raw[4:-4]==payload and struct.unpack('<I',raw[-4:])[0]==zlib.crc32(payload)
                download.append(bulk_n/elapsed)
            for _ in range(5):score(link,case)
            samples=[];core_ticks=[];board_ticks=[];stream_start=time.perf_counter_ns()
            for _ in range(100):
                elapsed,words=score(link,case);samples.append(elapsed/1e3);core_ticks.append(words[3]/hello[2]*1e6);board_ticks.append(words[4]/hello[2]*1e6)
            stream_seconds=(time.perf_counter_ns()-stream_start)/1e9
            result['uart'][str(baud)]={'framing':'8N1','request_bytes':2409,'response_bytes':136,'bulk_payload_bytes':bulk_n,'upload_bytes_per_second':summary(upload),'board_rx_bytes_per_second':summary(board_rx),'download_bytes_per_second':summary(download),'full_request_rtt_us':summary(samples),'compute_start_to_irq_us':summary(core_ticks),'board_upload_compute_readback_us':summary(board_ticks),'sustained_host_updates_per_second':100/stream_seconds}
            print('UART',baud,json.dumps(result['uart'][str(baud)]),flush=True)
            Path(a.output).write_text(json.dumps(result,indent=2)+'\n')
        score(link,case)
        link.write(b'B'+struct.pack('<I',1000));magic,count,hz,total,errors,irqs=struct.unpack('<6I',link.read(24))
        assert magic==0x31484342 and errors==0 and irqs==count
        raw=link.read(count*16);assert struct.unpack('<I',link.read(4))[0]==zlib.crc32(raw)
        records=list(struct.iter_unpack('<4I',raw));assert all(r[2]==725 and r[3]==0 for r in records)
        result['on_board']={'samples':count,'verified_interrupts':irqs,'errors':errors,'compute_cycles':725,'timer_hz':hz,'elapsed_ticks':total,'full_axi_transaction_us':summary([r[0]/hz*1e6 for r in records]),'compute_start_to_irq_us':summary([r[1]/hz*1e6 for r in records]),'sustained_updates_per_second':count*hz/total}
        Path(a.output).write_text(json.dumps(result,indent=2)+'\n')
        print('Saved',a.output,flush=True)
    finally:link.close()
if __name__=='__main__':main()
