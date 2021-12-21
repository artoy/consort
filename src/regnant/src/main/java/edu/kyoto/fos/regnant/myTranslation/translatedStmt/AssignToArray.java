package edu.kyoto.fos.regnant.myTranslation.translatedStmt;

import edu.kyoto.fos.regnant.myTranslation.TranslatedUnit;
import edu.kyoto.fos.regnant.myTranslation.TranslatedValue;
import edu.kyoto.fos.regnant.myTranslation.Service.TranslateExprService;
import soot.jimple.internal.JArrayRef;
import soot.jimple.internal.JAssignStmt;

import java.util.List;

// 配列に代入する式を表すクラス
public class AssignToArray implements TranslatedUnit {
	// arrayName は配列名, index は配列の中の代入されるインデックス, value は代入される値を表す
	private final String arrayName;
	private final String index;
	private final TranslatedValue value;

	public AssignToArray(JAssignStmt unit) {
		TranslateExprService handler = new TranslateExprService();

		this.arrayName = ((JArrayRef) (unit.getLeftOp())).getBase().toString();
		this.index = ((JArrayRef) (unit.getLeftOp())).getIndex().toString();
		this.value = handler.translate(unit.getRightOp());
	}

	public boolean isSequencing() {
		return true;
	}

	public boolean istTranslatedUnitEmpty() {
		return false;
	}

	public String print(List<String> arguments) {
		StringBuilder builder = new StringBuilder();
		builder
						.append(arrayName)
						.append("[")
						.append(index)
						.append("] <- ")
						.append(value.print(false))
						.append(";");

		return builder.toString();
	}
}
