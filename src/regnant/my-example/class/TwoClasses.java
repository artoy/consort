public class TwoClasses {
    public static void main(String[] args) {
        Point p = new Point(3);
        Point p2 = new DoublePoint(5, 10);

        int s = p.getx();

        p2.setx(20);
        int t = p2.getx();
    }
}

class Point {
    int x;

    Point (int x) {
        this.x = x;
    }

    int getx() {
        return x;
    }

    void setx(int x) {
        this.x = x;
    }
}

class DoublePoint extends Point {
    int y;

    DoublePoint (int x, int y) {
        super(x);
        this.y = y;
    }

    int gety() {
        return y;
    }

    void sety(int y) {
        this.y = y;
    }

    void setx(int x) {
        this.x = 2 * x;
    }
}
