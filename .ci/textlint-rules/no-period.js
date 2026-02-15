/**
 * 句点（。）の使用を禁止するtextlintルールです
 */
module.exports = function (context) {
  const { Syntax, RuleError, report, getSource } = context;

  return {
    [Syntax.Paragraph](node) {
      const text = getSource(node);
      const match = text.indexOf("。");
      if (match !== -1) {
        report(
          node,
          new RuleError("句点（。）は使用しないでください", {
            index: match,
          })
        );
      }
    },
  };
};
