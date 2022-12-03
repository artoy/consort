public class foo2 {
    public static void main(String[] args) {
        O p = new O();
        O2 q = new O2();
        p = q;

        O3 r = new O3();
    }
}

class O {
    int x;

    O () {
        x = 5;
    }
}

class O2 extends O {
    int y;

    O2 () {
        y = 10;
    }
}

class O3 {
    int a, b, c;

    O3 () {
        a = 1;
        b = 2;
        c = 3;
    }
}


