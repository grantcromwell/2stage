import java.nio.file.*;
import java.util.*;
public final class ShadowScoreBenchmark {
    record Case(int n, boolean sat, boolean error, long q, int[] a, int[] x, int[] expected) {}
    static volatile long sink;
    static long score(Case c,int[] y) {
        Arrays.fill(y,0);
        if(c.n<1||c.n>24)return 0;
        for(int r=0;r<c.n;r++) {
            long sum=0;
            for(int k=0;k<c.n;k++)sum+=((long)c.a[r*24+k]*c.x[k])>>16;
            y[r]=(int)Math.max(Integer.MIN_VALUE,Math.min(Integer.MAX_VALUE,sum));
        }
        long q=0;for(int k=0;k<c.n;k++)q+=((long)c.x[k]*y[k])>>16;
        return q;
    }
    public static void main(String[] args)throws Exception {
        Scanner s=new Scanner(Files.readString(Path.of(args[0])));
        ArrayList<Case> cases=new ArrayList<>(),full=new ArrayList<>();
        for(int t=0;t<80;t++) {
            int n=Integer.parseInt(s.next(),16);boolean sat=Integer.parseInt(s.next(),16)!=0,error=Integer.parseInt(s.next(),16)!=0;
            long q=Long.parseUnsignedLong(s.next(),16);
            int[] a=new int[576],x=new int[24],expected=new int[24];
            for(int i=0;i<a.length;i++)a[i]=(int)Long.parseLong(s.next(),16);
            for(int i=0;i<x.length;i++)x[i]=(int)Long.parseLong(s.next(),16);
            for(int i=0;i<expected.length;i++)expected[i]=(int)Long.parseLong(s.next(),16);
            Case c=new Case(n,sat,error,q,a,x,expected);cases.add(c);if(n==24)full.add(c);
        }
        int[] y=new int[24];
        for(Case c:cases)if(score(c,y)!=c.q||!Arrays.equals(y,c.expected))throw new AssertionError("Oracle mismatch n="+c.n);
        long warmup=System.nanoTime()+3_000_000_000L,checksum=0,calls=0;
        while(System.nanoTime()<warmup)for(int i=0;i<4096;i++){Case c=full.get((int)(calls++%full.size()));checksum+=score(c,y)+y[23];}
        sink=checksum;
        double[] sample=new double[40];long total=0;final int batch=10000;
        for(int b=0;b<sample.length;b++) {
            long begin=System.nanoTime();
            for(int i=0;i<batch;i++){Case c=full.get((int)(calls++%full.size()));checksum+=score(c,y)+y[23];}
            long elapsed=System.nanoTime()-begin;total+=elapsed;sample[b]=elapsed/(double)batch;sink=checksum;
        }
        Arrays.sort(sample);
        System.out.printf(Locale.ROOT,"{\"workload\":\"Q16.16 matrix score y=A*x and q=xT*y; not full Kalman\",\"dimension\":24,\"parity_cases\":80,\"dataset_cases\":%d,\"warmup_seconds\":3,\"batches\":40,\"calls_per_batch\":10000,\"mean_ns_per_call\":%.3f,\"p50_batch_ns_per_call\":%.3f,\"p95_batch_ns_per_call\":%.3f,\"checksum\":%d,\"java_version\":\"%s\",\"vm\":\"%s\"}%n",full.size(),total/(double)(batch*sample.length),sample[19],sample[37],sink,System.getProperty("java.version"),System.getProperty("java.vm.name"));
    }
}
