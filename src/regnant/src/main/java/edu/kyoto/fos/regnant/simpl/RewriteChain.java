package edu.kyoto.fos.regnant.simpl;

import edu.kyoto.fos.regnant.aliasing.AliasInsertion;
import soot.Body;

import java.util.List;
import java.util.function.Function;

// 変換前の Jimple の前処理を行うクラス
public class RewriteChain {
  private static final List<Function<Body, Body>> rewriters = List.of(
      AssertionRewriter::rewrite,
      RandomRewriter::rewriteRandom,
      AliasInsertion::rewrite
  );
  public static Body rewrite(Body b) {
    Body it = b;
    // 前処理の適用
    for(var f : rewriters) {
      it = f.apply(it);
    }
    return it;
  }

}
