public class sum_continue {
  public static void main(String[] args) {
    int ans = 0;

    for (int i = 0; i < 10; i++) {
      if (i > 5) {
        continue;
      }

      ans += i;
    }

    assert(ans == 16);
  }
}
