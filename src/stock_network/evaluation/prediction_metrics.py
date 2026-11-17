import numpy as np


def error_metrics(prediction, truth):
    error = np.asarray(prediction) - np.asarray(truth)
    mse = float(np.mean(error ** 2))
    return {"mse": mse, "rmse": float(np.sqrt(mse)), "mae": float(np.mean(np.abs(error)))}
