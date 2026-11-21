import java.nio.ByteBuffer;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import java.util.concurrent.*;
import java.util.zip.Deflater;

public class RssBenchmark {
    private static final List<ByteBuffer> PINNED = Collections.synchronizedList(new ArrayList<>());

    public static void main(String[] args) throws Exception {
        int threads = args.length > 0 ? Integer.parseInt(args[0]) : 64;
        String maps = Files.readString(Path.of("/proc/self/maps"));
        String allocator = maps.contains("jemalloc") ? "jemalloc" : "glibc (default)";

        System.out.println("=== Native Memory RSS Benchmark ===");
        System.out.println("Allocator : " + allocator);
        System.out.println("CPU Cores : " + Runtime.getRuntime().availableProcessors());
        System.out.println("Threads   : " + threads);
        printStats("0. Baseline");

        ExecutorService pool = Executors.newFixedThreadPool(threads);
        CountDownLatch startLatch = new CountDownLatch(1);
        CountDownLatch doneLatch = new CountDownLatch(threads);

        byte[] sampleData = new byte[8192];
        new Random(42).nextBytes(sampleData);

        for (int t = 0; t < threads; t++) {
            final int tid = t;
            pool.submit(() -> {
                try {
                    startLatch.await();
                    Random rnd = new Random(tid + 100);
                    List<ByteBuffer> local = new ArrayList<>(120);
                    byte[] out = new byte[8192];

                    for (int round = 0; round < 350; round++) {
                        // أحجام من 4KB لـ 36KB عشان تضرب الـ Memory Arenas مش mmap المباشر
                        int size = (1 + rnd.nextInt(9)) * 4096;
                        ByteBuffer buf = ByteBuffer.allocateDirect(size);
                        // لازم نلمس كل 4KB page عشان الـ Linux يحجز RAM فعلية في الـ RSS
                        for (int i = 0; i < size; i += 4096) {
                            buf.put(i, (byte) round);
                        }
                        local.add(buf);

                        // استدعاء zlib Deflater عشان يحاكي native malloc/free الحقيقي
                        Deflater deflater = new Deflater();
                        deflater.setInput(sampleData);
                        deflater.finish();
                        deflater.deflate(out);
                        deflater.end();

                        if (local.size() > 100) {
                            local.remove(rnd.nextInt(local.size()));
                        }
                    }

                    // بنثبت 1KB بس لكل thread (إجمالي 64KB) لمحاكاة metadata حقيقية عايشة
                    ByteBuffer tiny = ByteBuffer.allocateDirect(1024);
                    tiny.put(0, (byte) 1);
                    PINNED.add(tiny);

                    local.clear();
                } catch (Exception e) {
                    e.printStackTrace();
                } finally {
                    doneLatch.countDown();
                }
            });
        }

        startLatch.countDown();

        while (!doneLatch.await(2, TimeUnit.SECONDS)) {
            printStats("1. Under Load");
        }
        printStats("2. Peak (End of Load)");

        pool.shutdown();
        pool.awaitTermination(5, TimeUnit.SECONDS);

        System.gc();
        Thread.sleep(1000);
        System.gc();
        printStats("3. After GC (0s)");

        // نراقب رجوع الذاكرة للـ kernel لمدة 30 ثانية (عشان jemalloc decay يشتغل)
        for (int sec = 5; sec <= 30; sec += 5) {
            Thread.sleep(5000);
            printStats("4. Cooldown (+" + sec + "s)");
        }
    }

    private static void printStats(String phase) throws Exception {
        long heapMB = (Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory()) / (1024 * 1024);
        String rssLine = Files.readAllLines(Path.of("/proc/self/status")).stream()
                .filter(l -> l.startsWith("VmRSS:"))
                .findFirst()
                .orElse("VmRSS: 0 kB");
        long rssKB = Long.parseLong(rssLine.replaceAll("[^0-9]", ""));
        long rssMB = rssKB / 1024;
        System.out.printf("%-22s | Heap Used: %3d MB | VmRSS: %4d MB%n", phase, heapMB, rssMB);
    }
}