package edu.kyoto.fos.regnant.translation;

import edu.kyoto.fos.regnant.ir.expr.ImpExpr;
import edu.kyoto.fos.regnant.ir.stmt.aliasing.AliasOp;
import edu.kyoto.fos.regnant.ir.stmt.aliasing.AliasOp.Builder;
import edu.kyoto.fos.regnant.storage.oo.StorageLayout;
import soot.SootField;
import soot.Type;

import java.util.LinkedList;
import java.util.function.Function;

public interface ObjectModel {
  enum Impl {
    // これを取り出すと new が呼ばれる？
    FUNCTIONAL(FunctionalTupleModel::new),
    MUTABLE(MutableTupleModel::new);

    private final Function<StorageLayout, ObjectModel> fact;

    // やってることは実質 DI
    // これによってどっちのオブジェクトモデルを採用するか、どのようにしてオブジェクトモデルを作成するかが決められる（その方法が factory）
    Impl(Function<StorageLayout, ObjectModel> factory) {
      this.fact = factory;
    }

    // StorageLayout からオブジェクトを表すタプルを作成するメソッド
    public ObjectModel make(StorageLayout sl) {
      return fact.apply(sl);
    }
  }

  void writeField(InstructionStream l, String objectVar, SootField f, ImpExpr lhs, VarManager vm, LinkedList<Cleanup> handlers);
  FieldContents readField(InstructionStream l, String objectVar, SootField f, VarManager vm, LinkedList<Cleanup> handlers);

  Builder extendAP(AliasOp.Builder b, SootField f);

  default void iterAP(SootField f, AliasOp.Builder b) {
    extendAP(b, f);
  }
  ImpExpr allocFieldOfType(Type t);
}
