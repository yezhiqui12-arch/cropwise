# Pest species model

`wormwise_pest_species_yolov8n_640_float32.tflite` was exported from the
user-supplied `best (2).pt` checkpoint with Ultralytics 8.3.230 using
`format='tflite', imgsz=640, half=False, int8=False, nms=False`.

- Source SHA-256: `69F0FA60696F5A80408FDE25A3C13BC678CCAD771E09B61EB5139D4D95F25B44`
- Export SHA-256: `F235E72BB4F79123D57FA23596A9F2A0FD8E19B4DEFC68992ADE6CB7AC4E8778`
- Input: float32 `[1, 640, 640, 3]`, RGB scaled to 0–1.
- Output: float32 `[1, 7, 8400]`, normalized `xywh` plus three class scores.
- Checkpoint class order: 0 corn earworm, 1 cutworm, 2 fall armyworm.

The app runs this detector only on a crop around a larva box from the existing
second-stage FAW evidence detector. Its labels are suggestions and do not
change evaluator-confirmed observations or Davis severity scores.
