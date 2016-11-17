import mdk.Functions;
import mdk.MDK;
import mdk.Session;

public class Resolve {
    public static void main(String[] args) {
        MDK mdk = Functions.start();
        Session ssn = mdk.session();
        String address = ssn.resolve_until(args[0], "1.0.0", 10.0).address;
        System.out.println(address);
        mdk.stop();
    }
}
