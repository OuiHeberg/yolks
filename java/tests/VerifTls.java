// Connexion TLS vers <hôte>:443 avec le magasin de certificats par défaut du JDK, comme un
// serveur Minecraft qui télécharge en HTTPS. Lancé par java/tests/racines-tls.sh, en mode
// « fichier source » (Java 11 et plus) : java VerifTls.java <hôte>
// Affiche la chaîne ENVOYÉE par le serveur, puis le verdict.
// Code de sortie : 0 chaîne acceptée, 2 chaîne refusée (certificat), 3 hôte injoignable.
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.security.cert.Certificate;
import java.security.cert.X509Certificate;
import javax.net.ssl.SSLHandshakeException;
import javax.net.ssl.SSLParameters;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.SSLSocketFactory;

public class VerifTls {
    public static void main(String[] args) {
        String hote = args[0];
        Socket brut = new Socket();
        try {
            brut.connect(new InetSocketAddress(hote, 443), 10000);
            brut.setSoTimeout(10000);
        } catch (IOException e) {
            System.out.println("INJOIGNABLE " + hote + " : " + e);
            System.exit(3);
        }
        try (SSLSocket s = (SSLSocket) ((SSLSocketFactory) SSLSocketFactory.getDefault()).createSocket(brut, hote, 443, true)) {
            SSLParameters p = s.getSSLParameters();
            p.setEndpointIdentificationAlgorithm("HTTPS");
            s.setSSLParameters(p);
            s.startHandshake();
            for (Certificate c : s.getSession().getPeerCertificates()) {
                X509Certificate x = (X509Certificate) c;
                System.out.println("  " + x.getSubjectX500Principal().getName() + "  <-  " + x.getIssuerX500Principal().getName());
            }
            System.out.println("ACCEPTÉ " + hote);
            System.exit(0);
        } catch (SSLHandshakeException e) {
            System.out.println("REFUSÉ " + hote + " : " + e.getMessage());
            System.exit(2);
        } catch (IOException e) {
            System.out.println("INJOIGNABLE " + hote + " : " + e);
            System.exit(3);
        }
    }
}
