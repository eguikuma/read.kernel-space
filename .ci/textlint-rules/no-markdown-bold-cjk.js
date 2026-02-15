/**
 * Markdown太字記法（**text**）を禁止するtextlintルールです
 *
 * **text**記法はCJK文字の直後または直前で正しくレンダリングされない場合があるため、<strong>タグの使用を強制します
 */
module.exports = function (context) {
  const { Syntax, RuleError, report } = context;

  return {
    [Syntax.Strong](node) {
      report(
        node,
        new RuleError(
          "**text**記法は禁止のため、<strong>タグを使用してください"
        )
      );
    },
  };
};
