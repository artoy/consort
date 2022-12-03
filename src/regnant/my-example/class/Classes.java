public class Classes {
    public static void main(String[] args) {
        Point p = new Point(3);
        p = new DoublePoint(5, 10);
    }
}

class Point {
    int x;

    Point (int x) {
        this.x = x;
    }
}

class DoublePoint extends Point {
    int y;

    DoublePoint (int x, int y) {
        super(x);
        this.y = y;
    }
}


