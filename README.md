# Setups for SPICE (Starter Package for ICON-CLM Experiments)

This repo serves as a collection of setups for SPICE on CSCS Alps/Säntis.

## Usage

It is recommended put the setups into a `experiments` folder
of your [SPICE](https://github.com/C2SM/spice) root directory and clone this repo inside of it.

```bash
cd ${SPICE_DIR}
git clone git@github.com:C2SM/spice-setups.git experiments
cd experiments
```

Afterwards create a copy of an existing case, rename it and adapt the 
`job_settings` file. For example, to create your own ERA5-driven case:

```bash
cp -r IAEVALL03 MYEVALRUN01
cd MYEVALRUN01
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