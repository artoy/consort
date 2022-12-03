public class mult_class {
    public static void main(String[] args) {
        int x, y;
        x = 10;

        sum s = new sum(1, 2);

        y = x + s.result();
        assert(y == 13);
    }
}

class sum {
    private int a, b;

    public sum(int a, int b) {
        this.a = a;
        this.b = b;
    }

    public int result() {
        return a + b;
    }
}
