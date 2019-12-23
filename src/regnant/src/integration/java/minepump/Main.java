package minepump;

import annotation.SkipTest;

import java.util.Random;

public  class  Main {

  private static final int cleanupTimeShifts = 2;

  @SkipTest
  public static void main(String[] args) {
    randomSequenceOfActions(3);
  }

  public static boolean getBoolean() {
    Random random = new Random();
    return random.nextInt() == 0;
  }


  public static void randomSequenceOfActions(int maxLength) {
    Actions a = new Actions();

    int counter = 0;
    while (counter < maxLength) {
      counter++;

      boolean action1 = getBoolean();
      boolean action2 = getBoolean();
      boolean action3 = getBoolean();
      boolean action4 = false;
      if (!action3) action4 = getBoolean();

      if (action1) {
        a.waterRise();
      }

      if (action2) {
        a.methaneChange();
      }

      if (action3) {
        a.startSystem();
      } else if (action4) {
        a.stopSystem();
      }

      a.timeShift();
    }

    for (counter = 0; counter < cleanupTimeShifts; counter++) {
      a.timeShift();
    }
  }
}
