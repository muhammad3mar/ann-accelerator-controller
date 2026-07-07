# Digits dataset export

`extract_digits_to_csv.py` exports the scikit-learn **8×8 handwritten digits** dataset to a CSV file for offline use (e.g. stimulus generation or analysis).

## Requirements

- Python 3.8+
- `numpy`
- `scikit-learn`

## Usage

From the project root:

```bash
python data/extract_digits_to_csv.py
```

The script writes **`digits_8x8_dataset.csv`** in the current working directory (project root when run as above).

## Output format

Each row is one sample:

- **Columns 0–63:** pixel values (`pixel_0` … `pixel_63`), integers 0–16
- **Column 64:** digit label (`label`), 0–9

The file includes a header row. There are **1797** samples (64 features + 1 label per row).
