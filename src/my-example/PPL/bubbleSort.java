public class bubbleSort {
    public static void main(String[] args) {
        int[] arr = { 0, 9, 3, 15, 8, 9, 6, 13 };

        int[] sorted = sort(arr);

        for (int i = 0; i < sorted.length - 1; i++) {
            assert(sorted[i] <= sorted[i + 1]);
        }
    }

    public static int[] sort(int[] arr){
        int tmp;

        for (int i = 0; i < arr.length; i++) {
            for (int j = 0; j < arr.length - i - 1; j++) {
                if (arr[j] > arr[j + 1]) {
                    tmp = arr[j];
                    arr[j] = arr[j + 1];
                    arr[j + 1] = tmp;
                }
            }
        }

        return arr;
    }
}
