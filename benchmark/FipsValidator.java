import java.security.Security;
import java.security.Provider;
import javax.crypto.Cipher;

public class FipsValidator {
    public static void main(String[] args) throws Exception {
        System.out.println("==================================================");
        System.out.println("  FIPS 140-3 Compliance & Security Verification  ");
        System.out.println("==================================================");
        
        System.out.println("\n[Active Security Providers]");
        Provider[] providers = Security.getProviders();
        for (int i = 0; i < providers.length; i++) {
            System.out.printf("  %d. %-10s (version %s)\n", i + 1, providers[i].getName(), providers[i].getVersionStr());
        }
        
        // 1. Verify BCFIPS is registered as Provider #1
        if (providers.length == 0 || !providers[0].getName().equals("BCFIPS")) {
            System.err.println("FAIL: BCFIPS is not primary security provider!");
            System.exit(1);
        }
        
        // 2. Test AES cipher from BCFIPS
        Cipher aes = Cipher.getInstance("AES/CBC/PKCS7Padding", "BCFIPS");
        System.out.println("\n[Cryptographic Self-Test]");
        System.out.println("  ✓ AES/CBC/PKCS7Padding cipher provider: " + aes.getProvider().getName());
        
        // 3. Test non-approved algorithm fails under approved_only mode
        try {
            Cipher des = Cipher.getInstance("DES/CBC/PKCS5Padding", "BCFIPS");
            System.err.println("FAIL: Non-approved cipher DES was accepted!");
            System.exit(1);
        } catch (Exception e) {
            System.out.println("  ✓ Non-approved cipher (DES) strictly blocked: " + e.getMessage());
        }
        
        // 4. Verify Truststore
        String trustStoreType = System.getProperty("javax.net.ssl.trustStoreType");
        System.out.println("\n[TrustStore Verification]");
        System.out.println("  ✓ TrustStore Type: " + trustStoreType);
        if (!"BCFKS".equalsIgnoreCase(trustStoreType)) {
            System.err.println("FAIL: Truststore is not BCFKS!");
            System.exit(1);
        }
        
        System.out.println("\n[RESULT] FIPS 140-3 Enforcement Verified Successfully!");
    }
}
