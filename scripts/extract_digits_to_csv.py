import numpy as np
from sklearn.datasets import load_digits
import os

# --- Configuration ---
OUTPUT_FILENAME = 'digits_8x8_dataset.csv'

def extract_and_save_digits(filename: str):
    """
    Loads the scikit-learn 8x8 digits dataset and saves it to a CSV file.
    The format of each row will be: pixel_0, pixel_1, ..., pixel_63, label (64 features + 1 label).
    """
    print("1. Loading the 8x8 Digits dataset from scikit-learn...")
    
    # Load the dataset
    # The 'data' attribute contains 1797 samples, each with 64 features (8*8=64)
    # The 'target' attribute contains the corresponding digit (0-9)
    digits = load_digits()
    X = digits.data  # Features (64 columns)
    y = digits.target # Labels (1 column)

    print(f"   - Samples loaded: {X.shape[0]}")
    print(f"   - Features per sample: {X.shape[1]}")
    
    # 2. Combine the features (X) and the labels (y)
    # We use np.c_ to concatenate them column-wise: [X_data | y_label]
    combined_data = np.c_[X, y]
    
    # 3. Create the CSV header string
    # Pixel column names (e.g., pixel_0, pixel_1, ..., pixel_63)
    pixel_columns = [f'pixel_{i}' for i in range(X.shape[1])]
    header = ",".join(pixel_columns + ['label'])

    # 4. Save the combined array to a CSV file
    print(f"2. Saving data to {os.path.abspath(filename)}...")
    
    try:
        # fmt='%d' ensures the floating-point pixel values are saved as integers
        np.savetxt(
            filename,
            combined_data,
            delimiter=",",
            fmt='%d',
            header=header,
            comments='' # Prevents '#' from appearing at the start of the header
        )
        print("3. Success! Data extraction complete.")
    except Exception as e:
        print(f"An error occurred while saving the file: {e}")

if __name__ == "__main__":
    extract_and_save_digits(OUTPUT_FILENAME)