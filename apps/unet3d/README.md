# U-Net3D

## Prepare data

> Taken from https://github.com/mlcommons/training/tree/master/retired_benchmarks/unet3d/pytorch

In LC and for `iopp` groups, you can get it in `/p/lustre3/iopp/dataset/ml-workloads/unet3d`, no need to redo process below

### Downloading the data

```bash
./prepare-data/1.download-data.sh
```

### Preprocess dataset

```bash
./prepare-data/2.preprocess-data.sh --input ./raw-data-dir/kits19/data/ --output <OUTPUT>
```


## Run Original Pipeline

- In LC

```
flux alloc -N <NUM_NODES> -q pdebug
apps/unet3d/run.sh
```


## Run DLIO Pipeline

- In LC

```
flux alloc -N <NUM_NODES> -q pdebug
apps/unet3d/run-dlio.sh
```
