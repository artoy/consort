import data.C;

public class ObjectEquality3 {
    public static void main(String[] args) {
        C a = new C();
        C b = a;
        a.setJ(12);

        // won't work unless ifptr is implemented differently
        // assert(a == b);
    }
}