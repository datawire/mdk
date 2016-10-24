import java.util.ArrayList;
import java.util.Collections;
import mdk.Functions;
import mdk.MDKImpl;
import mdk.Session;
import mdk_tracing.protocol.LogEvent;

public class WriteLogs {
    public static void main(String[] args) {
        MDKImpl mdk = (MDKImpl)Functions.start();
        long start = System.currentTimeMillis();
        Session session = mdk.session();
        session.trace("DEBUG");
        ArrayList<String> messages = new ArrayList<String>();
        String category = args[0];
        ArrayList<String> sent_messages = new ArrayList<String>();
        sent_messages.add("hello critical " + category);
        sent_messages.add("hello debug " + category);
        sent_messages.add("hello error " + category);
        sent_messages.add("hello info " + category);
        sent_messages.add("hello warn " + category);

        mdk._tracer.subscribe((Object o) -> {
            LogEvent event = (LogEvent)o;
            System.out.println("got: " + event.text);
            if (System.currentTimeMillis() - start > 60000) {
                System.out.println("Timeout");
                System.exit(1);
            }
            if (event.category.equals(category)) {
                messages.add(event.text);
            }
            if (messages.size() == 5) {
                mdk.stop();
                Collections.sort(messages);
                if (!messages.equals(sent_messages)) {
                    System.out.println("unexpected responses:");
                    System.out.println(messages.toString());
                    System.exit(1);
                } else {
                    System.out.println("got all messages");
                    System.exit(0);
                }
            }
            return true;
        });

        try {
            Thread.sleep(3000);
        } catch (InterruptedException e) {
            ;
        }
        session.critical(category, sent_messages.get(0));
        session.debug(category, sent_messages.get(1));
        session.error(category, sent_messages.get(2));
        session.info(category, sent_messages.get(3));
        session.warn(category, sent_messages.get(4));
    }
}
