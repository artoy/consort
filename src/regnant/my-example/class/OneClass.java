public class OneClass {
    public static void main(String[] args) {
        Point p = new Point(3);
        int s = p.getx();
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
}


