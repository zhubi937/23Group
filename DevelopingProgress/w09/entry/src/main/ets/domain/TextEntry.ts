// A phonetic input method owns its uncommitted preview. Do not replace the
// controlled value or rebuild the whole draft until a candidate is committed.
export function canCommitText(preview: string | undefined): boolean {
  return preview === undefined || preview.length === 0;
}
