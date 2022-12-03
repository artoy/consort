class O {
	int a;

	public O(int a) {
		this.a = a;
	}

	public int getA() {
		return a;
	}
}

class O2 extends O {
	int a = 1;
	int b;

	public O2(int a, int b) {
		super(a);
		this.b = b;
	}
}

public class Inheritance {
	public static void main(String[] args){
		O x = new O(1);
		O2 y = new O2(2, 3);

		int z = y.getA();
	}
}
