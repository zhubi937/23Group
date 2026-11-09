# Third-party notices

The offline OCR engine runs inside the application on the phone/emulator. No network OCR service is used.

- Tesseract 5.5.0: https://github.com/tesseract-ocr/tesseract/tree/5.5.0 — Apache License 2.0. Complete vendored source and license: `entry/src/main/cpp/third_party/tesseract-5.5.0`.
- Leptonica 1.85.0: https://github.com/DanBloomberg/leptonica/tree/1.85.0 — BSD-style Leptonica license. Complete vendored source and original license: `entry/src/main/cpp/third_party/leptonica-1.85.0/leptonica-license.txt`.
- tessdata_fast `chi_sim` and `eng`: https://github.com/tesseract-ocr/tessdata_fast/tree/87416418657359cb625c412a48b6e1d6d41c29bd — Apache License 2.0. Model bytes and SHA-256 hashes are recorded in `OCR_MODELS.json`. Model license: `entry/src/main/resources/rawfile/tessdata/LICENSE`.

The application package also contains license copies in `resources/rawfile/licenses/`.

## Local build adaptations

Tesseract CMake uses the bundled Leptonica target rather than searching host libraries, skips its TIFF runtime probe when TIFF is disabled, and skips its LTO capability probe when LTO is disabled. The OCR algorithm source is unchanged. The top-level CMake sets the cross-compilation policy, position-independent code and bounded compile jobs. Image file decoding uses HarmonyOS Image Kit; Leptonica image codecs, curl, archive, graphics, training tools and OpenMP are disabled. Only local RGBA pixels are passed to the asynchronous N-API wrapper.
