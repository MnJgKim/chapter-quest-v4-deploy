# Parent-reviewed PDF question production and reread scoring contract

## Scope
- Preserve currently deployed Zack Files material.
- For Magic Tree House Book 2 and later books, parent provides original chapter PDF through the project workflow. Assistant extracts source-aligned TXT, prepares chapter questions and answer keys, Korean translations/explanations and exact supporting PDF page references, and presents them in chat for parent review.
- Before presenting any question, cross-check the source PDF, answer key, page references, and Korean interpretation. Flag ambiguous text, missing pages, uncertain answers, or mismatched page references as **review required**; ask parent to inspect original PDF. Never invent source content or page numbers.
- **Only after explicit parent approval**, produce a downloadable JSON file compatible with the actual parent-admin import contract. Parent imports JSON and publishes/assigns using the parent-admin UI. Never assume a JSON schema without inspecting the implemented importer.
- An approval applies to the exact question+answer version. Edits after approval require re-review/re-approval; existing immutable student submissions retain their original version.
- Publishing a chapter and validating its answers is a per-chapter workflow; **do not require an inventory-wide audit of hidden chapters before shipping the generic reread feature**.

## Student-side invariant
- Every published question must have a nonempty valid response; MC choices may be guesses. Reading complete, essay, speaking script and uploaded recording remain required.
- At submission time the server scores MC responses against the matching approved question+key version. Correct / total MC < 70% shows reread warning; >= 70% does not. Applies to all currently registered, hidden and future chapters once they are studied.
- Student unanswered question and missing server answer key are distinct errors. Never silently treat a missing key as a passing score.
- Magic Tree House Book 2 Chapter 2 answer-content correction is explicitly excluded from this development task; it is not excluded from the generic scoring rule.

## Release safety
- No production SQL, Worker deployment, PR merge or student-data mutation without separate approval. Isolated integration and snapshot tests must pass before requesting release approval.
