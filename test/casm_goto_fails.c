/* `asm goto` must be refused BY NAME, not as "a non-empty template".
 *
 * It is a genuinely separate feature from the operand work: the template jumps
 * OUT of itself to a C label, so the label has to be visible to the encoder and
 * the block stops being a self-contained span of bytes. The x86-64 inline-asm
 * path resolves labels within one asm statement, which is what makes it safe
 * for the AST dead-code prune to delete an asm block behind a terminator —
 * ASTSubtreeHasLabel (ast_arena.inc) enumerates entry-point spellings and
 * AN_ASM is deliberately not among them.
 *
 * So whoever implements asm goto has a second thing to do, in a file this
 * ticket never touches: add AN_ASM to ASTSubtreeHasLabel. Missing it is not a
 * miscompile — the dispatch outgrows its target and the compiler says
 * "invalid IR jump target (label not defined)", which is how the C `case`
 * version of the same omission announced itself.
 *
 * This file must NOT compile.
 * feature-c-gnu-inline-asm-with-a-non-empty-template */
int main(void)
{
	asm goto ("jmp %l0" : : : : done);
	return 1;
done:
	return 0;
}
