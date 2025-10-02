# Setups for SPICE (Starter Package for ICON-CLM Experiments)

This repo serves as a collection of setups for SPICE on CSCS Alps/Säntis.


## Usage

### 1. Fork this repository

First, fork this repository on GitHub to your own namespace. This allows you to push changes to your own fork.

### 2. Add as a subtree

Add your fork as a subtree in the `experiments` folder of your [SPICE](https://github.com/C2SM/spice) root directory:

```bash
cd ${SPICE_DIR}
git subtree add --prefix=experiments git@github.com:<your-username>/spice-setups.git main --squash
cd experiments
```

### 3. Working with the subtree

To push changes made in the subtree back to your fork, use:

```bash
cd ${SPICE_DIR}
git subtree push --prefix=experiments git@github.com:<your-username>/spice-setups.git main
```

To pull updates from your fork into the subtree, use:

```bash
cd ${SPICE_DIR}
git subtree pull --prefix=experiments git@github.com:<your-username>/spice-setups.git main --squash
```

### 4. Create and modify your own case

Afterwards create a copy of an existing case, rename it and adapt the 
`job_settings` file. For example, to create your own ERA5-driven case:

```bash
cp -r IAEVALL03 MYEXP01
cd MYEXP01
```

Open `job_settings` and modify the following variables according to your needs:

- `SPDIR`
- `EXPID`
- `EXPDIR`
- `EMAIL_ADDRESS`
- `NOTIFICATION_ADDRESS`
- `PROJECT_ACCOUNT`
- `GA_TITLE`
- `GA_PROJECT_ID`
- `GA_CONTACT`

If everything is alright, start the chain:

```bash
./subchain start
```
