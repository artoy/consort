public class foo {
    public static void main(String[] args) {
        O p = new O();
        O2 q = new O2();
        p = q;
    }
}

class O {
    int x;

    O () {
        x = 0;
    }
}

class O2 extends O {
    int y;

    O2 () {
        y = 0;
    }
}


