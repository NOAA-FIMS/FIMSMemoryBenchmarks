# FIMS Benchmark Final Report

Generated: `2026-08-25 00:25:24 UTC`

## Model

The benchmark uses the `large` wrapper-built catch-at-age model with 120 years, 12 ages, two fleets, and 10,368 input rows.

It contains 139 fixed effects and 119 annual recruitment-deviation (`log_devs`) random effects, one for each year from 2 through 120.

Observed components include fishing catch, survey index, age compositions, length compositions, weight at age, and age-to-length conversion. Both branches start from identical parameters and use the same joint objective and `nlminb` controls for validation.

## Estimated parameters

| # | Type | Parameter | `main` | `dev-native-quadra` |
|---:|---|---|---:|---:|
| 1 | fixed | `Selectivity.1.inflection_point` | 1.713518034e+00 | 1.713520038e+00 |
| 2 | fixed | `Selectivity.1.slope` | 1.039699218e+00 | 1.039697644e+00 |
| 3 | fixed | `Fleet.1.log_Fmort.0` | -4.781809167e+00 | -4.781805735e+00 |
| 4 | fixed | `Fleet.1.log_Fmort.1` | -3.734883626e+00 | -3.734880983e+00 |
| 5 | fixed | `Fleet.1.log_Fmort.2` | -3.241494498e+00 | -3.241492437e+00 |
| 6 | fixed | `Fleet.1.log_Fmort.3` | -2.927119174e+00 | -2.927118162e+00 |
| 7 | fixed | `Fleet.1.log_Fmort.4` | -3.16249347e+00 | -3.162493063e+00 |
| 8 | fixed | `Fleet.1.log_Fmort.5` | -2.576378335e+00 | -2.576378215e+00 |
| 9 | fixed | `Fleet.1.log_Fmort.6` | -2.565781949e+00 | -2.565781376e+00 |
| 10 | fixed | `Fleet.1.log_Fmort.7` | -1.827491876e+00 | -1.827491555e+00 |
| 11 | fixed | `Fleet.1.log_Fmort.8` | -2.358643623e+00 | -2.358643419e+00 |
| 12 | fixed | `Fleet.1.log_Fmort.9` | -2.17399269e+00 | -2.173992506e+00 |
| 13 | fixed | `Fleet.1.log_Fmort.10` | -2.042987945e+00 | -2.04298822e+00 |
| 14 | fixed | `Fleet.1.log_Fmort.11` | -1.987318449e+00 | -1.987319126e+00 |
| 15 | fixed | `Fleet.1.log_Fmort.12` | -2.317281347e+00 | -2.317281682e+00 |
| 16 | fixed | `Fleet.1.log_Fmort.13` | -1.948743728e+00 | -1.948744697e+00 |
| 17 | fixed | `Fleet.1.log_Fmort.14` | -1.91736195e+00 | -1.917362623e+00 |
| 18 | fixed | `Fleet.1.log_Fmort.15` | -2.047790614e+00 | -2.047790851e+00 |
| 19 | fixed | `Fleet.1.log_Fmort.16` | -1.425689495e+00 | -1.42568931e+00 |
| 20 | fixed | `Fleet.1.log_Fmort.17` | -1.661331454e+00 | -1.661331077e+00 |
| 21 | fixed | `Fleet.1.log_Fmort.18` | -1.711423053e+00 | -1.711422256e+00 |
| 22 | fixed | `Fleet.1.log_Fmort.19` | -1.780123761e+00 | -1.78012291e+00 |
| 23 | fixed | `Fleet.1.log_Fmort.20` | -1.542519838e+00 | -1.542519315e+00 |
| 24 | fixed | `Fleet.1.log_Fmort.21` | -1.970072088e+00 | -1.970071566e+00 |
| 25 | fixed | `Fleet.1.log_Fmort.22` | -1.599233215e+00 | -1.599231899e+00 |
| 26 | fixed | `Fleet.1.log_Fmort.23` | -1.944134206e+00 | -1.944132537e+00 |
| 27 | fixed | `Fleet.1.log_Fmort.24` | -2.094411267e+00 | -2.094409513e+00 |
| 28 | fixed | `Fleet.1.log_Fmort.25` | -2.332947766e+00 | -2.332945951e+00 |
| 29 | fixed | `Fleet.1.log_Fmort.26` | -2.476912279e+00 | -2.476910458e+00 |
| 30 | fixed | `Fleet.1.log_Fmort.27` | -2.294978774e+00 | -2.294977467e+00 |
| 31 | fixed | `Fleet.1.log_Fmort.28` | -2.691028235e+00 | -2.691027184e+00 |
| 32 | fixed | `Fleet.1.log_Fmort.29` | -2.363512985e+00 | -2.363512789e+00 |
| 33 | fixed | `Fleet.1.log_Fmort.30` | -4.502966469e+00 | -4.50296684e+00 |
| 34 | fixed | `Fleet.1.log_Fmort.31` | -3.538593896e+00 | -3.538594327e+00 |
| 35 | fixed | `Fleet.1.log_Fmort.32` | -3.101527115e+00 | -3.101528012e+00 |
| 36 | fixed | `Fleet.1.log_Fmort.33` | -2.824699393e+00 | -2.8246997e+00 |
| 37 | fixed | `Fleet.1.log_Fmort.34` | -3.08675198e+00 | -3.0867528e+00 |
| 38 | fixed | `Fleet.1.log_Fmort.35` | -2.520746419e+00 | -2.52074685e+00 |
| 39 | fixed | `Fleet.1.log_Fmort.36` | -2.523850284e+00 | -2.523850875e+00 |
| 40 | fixed | `Fleet.1.log_Fmort.37` | -1.795295284e+00 | -1.79529642e+00 |
| 41 | fixed | `Fleet.1.log_Fmort.38` | -2.331802622e+00 | -2.331803406e+00 |
| 42 | fixed | `Fleet.1.log_Fmort.39` | -2.151406186e+00 | -2.151407232e+00 |
| 43 | fixed | `Fleet.1.log_Fmort.40` | -2.022766139e+00 | -2.022767177e+00 |
| 44 | fixed | `Fleet.1.log_Fmort.41` | -1.968988289e+00 | -1.968989528e+00 |
| 45 | fixed | `Fleet.1.log_Fmort.42` | -2.300737534e+00 | -2.300738766e+00 |
| 46 | fixed | `Fleet.1.log_Fmort.43` | -1.934153818e+00 | -1.934154652e+00 |
| 47 | fixed | `Fleet.1.log_Fmort.44` | -1.904264602e+00 | -1.904265376e+00 |
| 48 | fixed | `Fleet.1.log_Fmort.45` | -2.036270788e+00 | -2.036271344e+00 |
| 49 | fixed | `Fleet.1.log_Fmort.46` | -1.415643356e+00 | -1.41564365e+00 |
| 50 | fixed | `Fleet.1.log_Fmort.47` | -1.652072322e+00 | -1.652073328e+00 |
| 51 | fixed | `Fleet.1.log_Fmort.48` | -1.70302767e+00 | -1.703029251e+00 |
| 52 | fixed | `Fleet.1.log_Fmort.49` | -1.772375516e+00 | -1.772377169e+00 |
| 53 | fixed | `Fleet.1.log_Fmort.50` | -1.535354406e+00 | -1.535355343e+00 |
| 54 | fixed | `Fleet.1.log_Fmort.51` | -1.963674563e+00 | -1.963675694e+00 |
| 55 | fixed | `Fleet.1.log_Fmort.52` | -1.593798353e+00 | -1.593798833e+00 |
| 56 | fixed | `Fleet.1.log_Fmort.53` | -1.939303198e+00 | -1.939302509e+00 |
| 57 | fixed | `Fleet.1.log_Fmort.54` | -2.090125373e+00 | -2.0901244e+00 |
| 58 | fixed | `Fleet.1.log_Fmort.55` | -2.329131475e+00 | -2.329130689e+00 |
| 59 | fixed | `Fleet.1.log_Fmort.56` | -2.473531642e+00 | -2.473530494e+00 |
| 60 | fixed | `Fleet.1.log_Fmort.57` | -2.291955465e+00 | -2.291954569e+00 |
| 61 | fixed | `Fleet.1.log_Fmort.58` | -2.68830154e+00 | -2.688300811e+00 |
| 62 | fixed | `Fleet.1.log_Fmort.59` | -2.361041588e+00 | -2.361041261e+00 |
| 63 | fixed | `Fleet.1.log_Fmort.60` | -4.500699626e+00 | -4.500699365e+00 |
| 64 | fixed | `Fleet.1.log_Fmort.61` | -3.536566672e+00 | -3.536566293e+00 |
| 65 | fixed | `Fleet.1.log_Fmort.62` | -3.099664499e+00 | -3.099664176e+00 |
| 66 | fixed | `Fleet.1.log_Fmort.63` | -2.822942496e+00 | -2.822941867e+00 |
| 67 | fixed | `Fleet.1.log_Fmort.64` | -3.085076681e+00 | -3.085076496e+00 |
| 68 | fixed | `Fleet.1.log_Fmort.65` | -2.519141682e+00 | -2.519141564e+00 |
| 69 | fixed | `Fleet.1.log_Fmort.66` | -2.522282398e+00 | -2.522282327e+00 |
| 70 | fixed | `Fleet.1.log_Fmort.67` | -1.793699812e+00 | -1.793700294e+00 |
| 71 | fixed | `Fleet.1.log_Fmort.68` | -2.330123089e+00 | -2.330123071e+00 |
| 72 | fixed | `Fleet.1.log_Fmort.69` | -2.149671545e+00 | -2.149671321e+00 |
| 73 | fixed | `Fleet.1.log_Fmort.70` | -2.020922724e+00 | -2.020922645e+00 |
| 74 | fixed | `Fleet.1.log_Fmort.71` | -1.966986178e+00 | -1.96698627e+00 |
| 75 | fixed | `Fleet.1.log_Fmort.72` | -2.298571936e+00 | -2.298571786e+00 |
| 76 | fixed | `Fleet.1.log_Fmort.73` | -1.931790516e+00 | -1.931790671e+00 |
| 77 | fixed | `Fleet.1.log_Fmort.74` | -1.901607876e+00 | -1.90160768e+00 |
| 78 | fixed | `Fleet.1.log_Fmort.75` | -2.033286051e+00 | -2.033286112e+00 |
| 79 | fixed | `Fleet.1.log_Fmort.76` | -1.412119192e+00 | -1.412119001e+00 |
| 80 | fixed | `Fleet.1.log_Fmort.77` | -1.647791979e+00 | -1.64779209e+00 |
| 81 | fixed | `Fleet.1.log_Fmort.78` | -1.697959221e+00 | -1.697959505e+00 |
| 82 | fixed | `Fleet.1.log_Fmort.79` | -1.76641529e+00 | -1.766415425e+00 |
| 83 | fixed | `Fleet.1.log_Fmort.80` | -1.528182021e+00 | -1.528181706e+00 |
| 84 | fixed | `Fleet.1.log_Fmort.81` | -1.955155572e+00 | -1.955155503e+00 |
| 85 | fixed | `Fleet.1.log_Fmort.82` | -1.583747054e+00 | -1.583746525e+00 |
| 86 | fixed | `Fleet.1.log_Fmort.83` | -1.927481534e+00 | -1.927481452e+00 |
| 87 | fixed | `Fleet.1.log_Fmort.84` | -2.07665137e+00 | -2.076650767e+00 |
| 88 | fixed | `Fleet.1.log_Fmort.85` | -2.314058993e+00 | -2.314057993e+00 |
| 89 | fixed | `Fleet.1.log_Fmort.86` | -2.456933175e+00 | -2.456931282e+00 |
| 90 | fixed | `Fleet.1.log_Fmort.87` | -2.273586426e+00 | -2.27358434e+00 |
| 91 | fixed | `Fleet.1.log_Fmort.88` | -2.66809784e+00 | -2.668095719e+00 |
| 92 | fixed | `Fleet.1.log_Fmort.89` | -2.338887971e+00 | -2.338885925e+00 |
| 93 | fixed | `Fleet.1.log_Fmort.90` | -4.477082803e+00 | -4.477081202e+00 |
| 94 | fixed | `Fleet.1.log_Fmort.91` | -3.512137207e+00 | -3.512135647e+00 |
| 95 | fixed | `Fleet.1.log_Fmort.92` | -3.073956249e+00 | -3.073954701e+00 |
| 96 | fixed | `Fleet.1.log_Fmort.93` | -2.79550066e+00 | -2.795499085e+00 |
| 97 | fixed | `Fleet.1.log_Fmort.94` | -3.055743315e+00 | -3.055741768e+00 |
| 98 | fixed | `Fleet.1.log_Fmort.95` | -2.48734157e+00 | -2.487340198e+00 |
| 99 | fixed | `Fleet.1.log_Fmort.96` | -2.487227638e+00 | -2.487226592e+00 |
| 100 | fixed | `Fleet.1.log_Fmort.97` | -1.753346072e+00 | -1.753345601e+00 |
| 101 | fixed | `Fleet.1.log_Fmort.98` | -2.283603128e+00 | -2.28360319e+00 |
| 102 | fixed | `Fleet.1.log_Fmort.99` | -2.097258881e+00 | -2.097258816e+00 |
| 103 | fixed | `Fleet.1.log_Fmort.100` | -1.960883503e+00 | -1.960883795e+00 |
| 104 | fixed | `Fleet.1.log_Fmort.101` | -1.897551389e+00 | -1.89755232e+00 |
| 105 | fixed | `Fleet.1.log_Fmort.102` | -2.219664764e+00 | -2.219665649e+00 |
| 106 | fixed | `Fleet.1.log_Fmort.103` | -1.841609723e+00 | -1.841610968e+00 |
| 107 | fixed | `Fleet.1.log_Fmort.104` | -1.796053779e+00 | -1.79605523e+00 |
| 108 | fixed | `Fleet.1.log_Fmort.105` | -1.910501428e+00 | -1.9105038e+00 |
| 109 | fixed | `Fleet.1.log_Fmort.106` | -1.261478415e+00 | -1.26148111e+00 |
| 110 | fixed | `Fleet.1.log_Fmort.107` | -1.458548103e+00 | -1.458550384e+00 |
| 111 | fixed | `Fleet.1.log_Fmort.108` | -1.466848214e+00 | -1.466850309e+00 |
| 112 | fixed | `Fleet.1.log_Fmort.109` | -1.486104713e+00 | -1.486107017e+00 |
| 113 | fixed | `Fleet.1.log_Fmort.110` | -1.178331248e+00 | -1.178333737e+00 |
| 114 | fixed | `Fleet.1.log_Fmort.111` | -1.527299113e+00 | -1.52730252e+00 |
| 115 | fixed | `Fleet.1.log_Fmort.112` | -1.063797933e+00 | -1.063802999e+00 |
| 116 | fixed | `Fleet.1.log_Fmort.113` | -1.294562098e+00 | -1.294568872e+00 |
| 117 | fixed | `Fleet.1.log_Fmort.114` | -1.336639992e+00 | -1.33664929e+00 |
| 118 | fixed | `Fleet.1.log_Fmort.115` | -1.473248679e+00 | -1.473259488e+00 |
| 119 | fixed | `Fleet.1.log_Fmort.116` | -1.530316522e+00 | -1.530328249e+00 |
| 120 | fixed | `Fleet.1.log_Fmort.117` | -1.26292599e+00 | -1.262941438e+00 |
| 121 | fixed | `Fleet.1.log_Fmort.118` | -1.62331137e+00 | -1.623330346e+00 |
| 122 | fixed | `Fleet.1.log_Fmort.119` | -1.297013242e+00 | -1.297036163e+00 |
| 123 | fixed | `Selectivity.2.inflection_point` | 1.419915687e+00 | 1.419914664e+00 |
| 124 | fixed | `Selectivity.2.slope` | 2.274239584e+00 | 2.274242746e+00 |
| 125 | fixed | `Fleet.2.log_q` | -1.523680371e+01 | -1.52368027e+01 |
| 126 | fixed | `Recruitment.1.log_rzero` | 1.406227481e+01 | 1.406227508e+01 |
| 127 | fixed | `Recruitment.1.log_sd` | -1.131645106e+00 | -1.131645353e+00 |
| 128 | fixed | `Population.1.log_init_naa.0` | 1.388260192e+01 | 1.388260234e+01 |
| 129 | fixed | `Population.1.log_init_naa.1` | 1.375947909e+01 | 1.375947737e+01 |
| 130 | fixed | `Population.1.log_init_naa.2` | 1.352361488e+01 | 1.352361266e+01 |
| 131 | fixed | `Population.1.log_init_naa.3` | 1.336330588e+01 | 1.336330455e+01 |
| 132 | fixed | `Population.1.log_init_naa.4` | 1.307572647e+01 | 1.307573569e+01 |
| 133 | fixed | `Population.1.log_init_naa.5` | 1.294150821e+01 | 1.294150941e+01 |
| 134 | fixed | `Population.1.log_init_naa.6` | 1.279158468e+01 | 1.27915842e+01 |
| 135 | fixed | `Population.1.log_init_naa.7` | 1.231639748e+01 | 1.231639795e+01 |
| 136 | fixed | `Population.1.log_init_naa.8` | 1.216044074e+01 | 1.216043821e+01 |
| 137 | fixed | `Population.1.log_init_naa.9` | 1.208287335e+01 | 1.208286989e+01 |
| 138 | fixed | `Population.1.log_init_naa.10` | 1.192193733e+01 | 1.192193515e+01 |
| 139 | fixed | `Population.1.log_init_naa.11` | 1.326372881e+01 | 1.326371672e+01 |
| 140 | random | `Recruitment.1.log_devs.0` | 2.850855939e-01 | 2.850935937e-01 |
| 141 | random | `Recruitment.1.log_devs.1` | -3.215926011e-01 | -3.215923979e-01 |
| 142 | random | `Recruitment.1.log_devs.2` | -5.583262503e-01 | -5.583253756e-01 |
| 143 | random | `Recruitment.1.log_devs.3` | 4.898506258e-01 | 4.898465733e-01 |
| 144 | random | `Recruitment.1.log_devs.4` | 1.970874138e-01 | 1.970867466e-01 |
| 145 | random | `Recruitment.1.log_devs.5` | -2.13995093e-01 | -2.139933277e-01 |
| 146 | random | `Recruitment.1.log_devs.6` | 1.992617952e-01 | 1.992660079e-01 |
| 147 | random | `Recruitment.1.log_devs.7` | -1.886041711e-01 | -1.886027402e-01 |
| 148 | random | `Recruitment.1.log_devs.8` | 3.146350384e-02 | 3.14638058e-02 |
| 149 | random | `Recruitment.1.log_devs.9` | -5.187798295e-02 | -5.187957833e-02 |
| 150 | random | `Recruitment.1.log_devs.10` | -4.05611007e-01 | -4.056082308e-01 |
| 151 | random | `Recruitment.1.log_devs.11` | -1.254343398e-01 | -1.25437795e-01 |
| 152 | random | `Recruitment.1.log_devs.12` | 4.065761008e-02 | 4.065623449e-02 |
| 153 | random | `Recruitment.1.log_devs.13` | -1.427154929e-01 | -1.427153163e-01 |
| 154 | random | `Recruitment.1.log_devs.14` | 1.554606207e-01 | 1.554567352e-01 |
| 155 | random | `Recruitment.1.log_devs.15` | 1.66994087e-01 | 1.669945926e-01 |
| 156 | random | `Recruitment.1.log_devs.16` | -4.064149046e-01 | -4.064139169e-01 |
| 157 | random | `Recruitment.1.log_devs.17` | -1.794175756e-01 | -1.794195224e-01 |
| 158 | random | `Recruitment.1.log_devs.18` | -4.657798751e-01 | -4.657811451e-01 |
| 159 | random | `Recruitment.1.log_devs.19` | 5.607929983e-01 | 5.607948475e-01 |
| 160 | random | `Recruitment.1.log_devs.20` | 5.429866422e-01 | 5.429812962e-01 |
| 161 | random | `Recruitment.1.log_devs.21` | 7.133634666e-02 | 7.133241059e-02 |
| 162 | random | `Recruitment.1.log_devs.22` | -1.124200247e-01 | -1.124234096e-01 |
| 163 | random | `Recruitment.1.log_devs.23` | 5.256644169e-01 | 5.256664665e-01 |
| 164 | random | `Recruitment.1.log_devs.24` | 6.617007105e-02 | 6.617216337e-02 |
| 165 | random | `Recruitment.1.log_devs.25` | 2.972358513e-01 | 2.972364024e-01 |
| 166 | random | `Recruitment.1.log_devs.26` | 4.734721157e-01 | 4.734782644e-01 |
| 167 | random | `Recruitment.1.log_devs.27` | 4.062213576e-01 | 4.062233417e-01 |
| 168 | random | `Recruitment.1.log_devs.28` | 8.186729138e-03 | 8.187797063e-03 |
| 169 | random | `Recruitment.1.log_devs.29` | -1.375933749e-01 | -1.375955181e-01 |
| 170 | random | `Recruitment.1.log_devs.30` | 3.154453853e-01 | 3.15441684e-01 |
| 171 | random | `Recruitment.1.log_devs.31` | -2.967706619e-01 | -2.967663722e-01 |
| 172 | random | `Recruitment.1.log_devs.32` | -5.387238287e-01 | -5.387279035e-01 |
| 173 | random | `Recruitment.1.log_devs.33` | 5.063172467e-01 | 5.063154789e-01 |
| 174 | random | `Recruitment.1.log_devs.34` | 2.118034225e-01 | 2.118056318e-01 |
| 175 | random | `Recruitment.1.log_devs.35` | -2.021538757e-01 | -2.021501052e-01 |
| 176 | random | `Recruitment.1.log_devs.36` | 2.088553689e-01 | 2.088554502e-01 |
| 177 | random | `Recruitment.1.log_devs.37` | -1.8128904e-01 | -1.812869537e-01 |
| 178 | random | `Recruitment.1.log_devs.38` | 3.842628005e-02 | 3.842361692e-02 |
| 179 | random | `Recruitment.1.log_devs.39` | -4.576517603e-02 | -4.57651841e-02 |
| 180 | random | `Recruitment.1.log_devs.40` | -4.000319497e-01 | -4.000308772e-01 |
| 181 | random | `Recruitment.1.log_devs.41` | -1.200554717e-01 | -1.200587115e-01 |
| 182 | random | `Recruitment.1.log_devs.42` | 4.607633738e-02 | 4.607527025e-02 |
| 183 | random | `Recruitment.1.log_devs.43` | -1.377078061e-01 | -1.377085993e-01 |
| 184 | random | `Recruitment.1.log_devs.44` | 1.600228375e-01 | 1.600257363e-01 |
| 185 | random | `Recruitment.1.log_devs.45` | 1.7082711e-01 | 1.708295491e-01 |
| 186 | random | `Recruitment.1.log_devs.46` | -4.036856354e-01 | -4.036889024e-01 |
| 187 | random | `Recruitment.1.log_devs.47` | -1.771167697e-01 | -1.771202628e-01 |
| 188 | random | `Recruitment.1.log_devs.48` | -4.637703425e-01 | -4.637658399e-01 |
| 189 | random | `Recruitment.1.log_devs.49` | 5.626191227e-01 | 5.626172373e-01 |
| 190 | random | `Recruitment.1.log_devs.50` | 5.444901451e-01 | 5.444865607e-01 |
| 191 | random | `Recruitment.1.log_devs.51` | 7.254413287e-02 | 7.254160788e-02 |
| 192 | random | `Recruitment.1.log_devs.52` | -1.119097527e-01 | -1.119125652e-01 |
| 193 | random | `Recruitment.1.log_devs.53` | 5.258936752e-01 | 5.258962588e-01 |
| 194 | random | `Recruitment.1.log_devs.54` | 6.625497443e-02 | 6.62515984e-02 |
| 195 | random | `Recruitment.1.log_devs.55` | 2.971995613e-01 | 2.971957628e-01 |
| 196 | random | `Recruitment.1.log_devs.56` | 4.732692055e-01 | 4.732753231e-01 |
| 197 | random | `Recruitment.1.log_devs.57` | 4.058821869e-01 | 4.058797689e-01 |
| 198 | random | `Recruitment.1.log_devs.58` | 7.772916806e-03 | 7.776083042e-03 |
| 199 | random | `Recruitment.1.log_devs.59` | -1.380686379e-01 | -1.380729164e-01 |
| 200 | random | `Recruitment.1.log_devs.60` | 3.149935534e-01 | 3.149920469e-01 |
| 201 | random | `Recruitment.1.log_devs.61` | -2.972315411e-01 | -2.972321834e-01 |
| 202 | random | `Recruitment.1.log_devs.62` | -5.392055317e-01 | -5.392087204e-01 |
| 203 | random | `Recruitment.1.log_devs.63` | 5.057828484e-01 | 5.057896939e-01 |
| 204 | random | `Recruitment.1.log_devs.64` | 2.112415344e-01 | 2.112371975e-01 |
| 205 | random | `Recruitment.1.log_devs.65` | -2.028153338e-01 | -2.028139257e-01 |
| 206 | random | `Recruitment.1.log_devs.66` | 2.080499391e-01 | 2.08044991e-01 |
| 207 | random | `Recruitment.1.log_devs.67` | -1.822641215e-01 | -1.822628087e-01 |
| 208 | random | `Recruitment.1.log_devs.68` | 3.731615076e-02 | 3.731479655e-02 |
| 209 | random | `Recruitment.1.log_devs.69` | -4.706720623e-02 | -4.7063687e-02 |
| 210 | random | `Recruitment.1.log_devs.70` | -4.015239339e-01 | -4.01522138e-01 |
| 211 | random | `Recruitment.1.log_devs.71` | -1.217816334e-01 | -1.217780692e-01 |
| 212 | random | `Recruitment.1.log_devs.72` | 4.410881072e-02 | 4.410230525e-02 |
| 213 | random | `Recruitment.1.log_devs.73` | -1.400226058e-01 | -1.400257803e-01 |
| 214 | random | `Recruitment.1.log_devs.74` | 1.572612276e-01 | 1.57264701e-01 |
| 215 | random | `Recruitment.1.log_devs.75` | 1.6748713e-01 | 1.674924569e-01 |
| 216 | random | `Recruitment.1.log_devs.76` | -4.077411542e-01 | -4.077486142e-01 |
| 217 | random | `Recruitment.1.log_devs.77` | -1.819284405e-01 | -1.819328466e-01 |
| 218 | random | `Recruitment.1.log_devs.78` | -4.69417118e-01 | -4.694187632e-01 |
| 219 | random | `Recruitment.1.log_devs.79` | 5.557066893e-01 | 5.557087589e-01 |
| 220 | random | `Recruitment.1.log_devs.80` | 5.361869014e-01 | 5.361864269e-01 |
| 221 | random | `Recruitment.1.log_devs.81` | 6.301216129e-02 | 6.301055993e-02 |
| 222 | random | `Recruitment.1.log_devs.82` | -1.232398502e-01 | -1.232449914e-01 |
| 223 | random | `Recruitment.1.log_devs.83` | 5.127747045e-01 | 5.127684133e-01 |
| 224 | random | `Recruitment.1.log_devs.84` | 5.151665042e-02 | 5.151442162e-02 |
| 225 | random | `Recruitment.1.log_devs.85` | 2.806423866e-01 | 2.806445965e-01 |
| 226 | random | `Recruitment.1.log_devs.86` | 4.546202922e-01 | 4.546206049e-01 |
| 227 | random | `Recruitment.1.log_devs.87` | 3.85146256e-01 | 3.851453633e-01 |
| 228 | random | `Recruitment.1.log_devs.88` | -1.450065139e-02 | -1.449970408e-02 |
| 229 | random | `Recruitment.1.log_devs.89` | -1.61992084e-01 | -1.619951593e-01 |
| 230 | random | `Recruitment.1.log_devs.90` | 2.896138752e-01 | 2.896110068e-01 |
| 231 | random | `Recruitment.1.log_devs.91` | -3.242164768e-01 | -3.242117728e-01 |
| 232 | random | `Recruitment.1.log_devs.92` | -5.680242069e-01 | -5.680233099e-01 |
| 233 | random | `Recruitment.1.log_devs.93` | 4.735930394e-01 | 4.735965079e-01 |
| 234 | random | `Recruitment.1.log_devs.94` | 1.761442898e-01 | 1.761423652e-01 |
| 235 | random | `Recruitment.1.log_devs.95` | -2.416371982e-01 | -2.416324437e-01 |
| 236 | random | `Recruitment.1.log_devs.96` | 1.63790755e-01 | 1.637919063e-01 |
| 237 | random | `Recruitment.1.log_devs.97` | -2.324261981e-01 | -2.324273331e-01 |
| 238 | random | `Recruitment.1.log_devs.98` | -1.869887372e-02 | -1.869667481e-02 |
| 239 | random | `Recruitment.1.log_devs.99` | -1.107174453e-01 | -1.107175759e-01 |
| 240 | random | `Recruitment.1.log_devs.100` | -4.731331575e-01 | -4.731302913e-01 |
| 241 | random | `Recruitment.1.log_devs.101` | -2.035065035e-01 | -2.035035493e-01 |
| 242 | random | `Recruitment.1.log_devs.102` | -4.906232816e-02 | -4.905914419e-02 |
| 243 | random | `Recruitment.1.log_devs.103` | -2.485356089e-01 | -2.485348512e-01 |
| 244 | random | `Recruitment.1.log_devs.104` | 2.830916048e-02 | 2.830485984e-02 |
| 245 | random | `Recruitment.1.log_devs.105` | 1.134227827e-02 | 1.133926983e-02 |
| 246 | random | `Recruitment.1.log_devs.106` | -5.987438873e-01 | -5.987492078e-01 |
| 247 | random | `Recruitment.1.log_devs.107` | -4.120659781e-01 | -4.120637721e-01 |
| 248 | random | `Recruitment.1.log_devs.108` | -7.508280894e-01 | -7.508269621e-01 |
| 249 | random | `Recruitment.1.log_devs.109` | 2.374933472e-01 | 2.374970168e-01 |
| 250 | random | `Recruitment.1.log_devs.110` | 1.745602231e-01 | 1.745693852e-01 |
| 251 | random | `Recruitment.1.log_devs.111` | -3.542125871e-01 | -3.542112595e-01 |
| 252 | random | `Recruitment.1.log_devs.112` | -6.268681149e-01 | -6.268637284e-01 |
| 253 | random | `Recruitment.1.log_devs.113` | 4.800779065e-02 | 4.800652426e-02 |
| 254 | random | `Recruitment.1.log_devs.114` | -5.265774926e-01 | -5.265643774e-01 |
| 255 | random | `Recruitment.1.log_devs.115` | -1.354336814e-01 | -1.354237003e-01 |
| 256 | random | `Recruitment.1.log_devs.116` | 2.13985908e-01 | 2.140013312e-01 |
| 257 | random | `Recruitment.1.log_devs.117` | 4.630142823e-01 | 4.630299273e-01 |
| 258 | random | `Recruitment.1.log_devs.118` | -1.423993987e-01 | -1.423829069e-01 |

## Joint objective validation

Source report: [joint_validation_report.md](joint_validation_report.md)


Both branches use the same wrapper-built model, starting values, joint fixed/random objective, and `nlminb` controls.

### Optimization summary

| Git ref | Backend | Fixed | Random | Initial objective | Final objective | Final gradient norm | Convergence | Iterations | Function evals | Gradient evals | Elapsed |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| main | TMB | 139 | 119 | 168417.46 | 14115.796 | 0.043716689 | 0 | 951 | 1464 | 952 | 1.954s |
| dev-native-quadra | native | 139 | 119 | 168417.46 | 14115.796 | 0.029366961 | 0 | 966 | 1497 | 967 | 6.355s |

### Agreement

| Metric | Difference |
|---|---:|
| Initial objective absolute difference | 8.7311491e-11 |
| Initial parameters maximum absolute difference | 0 |
| Initial gradient maximum absolute difference | 1.7462298e-10 |
| Final objective absolute difference | 4.1545718e-08 |
| Final parameters maximum absolute difference | 2.2920784e-05 |
| Final gradient maximum absolute difference | 0.016600493 |
| Iteration count difference | 15 |
| Function evaluation count difference | 33 |
| Gradient evaluation count difference | 15 |

Parameter and gradient differences are calculated after aligning logical parameter names and converting `log_slope` to the natural slope scale.

Canonical parameter sets agree: **yes**. Convergence codes agree: **yes**.

## CPU profile

Source report: [cpu_profile_report.md](cpu_profile_report.md)


Generated: `2026-08-25T00:09:47+00:00`
Profiler: Instruments Time Profiler

### Summary

Each branch is sampled in a separate model run after its FIMS build is installed.

| Git ref | FIMS version | Capture status | Profile data |
|---|---:|---|---|
| main | 0.10.0.9000 | captured | [instruments_cpu_main_0.10.0.9000.xml](instruments_cpu_main_0.10.0.9000.xml) |
| dev-native-quadra | 0.10.0.9000 | captured | [instruments_cpu_dev-native-quadra_0.10.0.9000.xml](instruments_cpu_dev-native-quadra_0.10.0.9000.xml) |

### Hot symbols by branch

#### `main`

| Rank | Symbol | Samples |
|---:|---|---:|
| 1 | `TMBad::global::Complete<TMBad::global::ad_plain::MulOp_<true, true>>::reverse_decr(TMBad::ReverseArgs<double>&)` | 6.42% |
| 2 | `bcEval_loop` | 5.86% |
| 3 | `TMBad::global::Complete<TMBad::global::ad_plain::AddOp_<true, true>>::reverse_decr(TMBad::ReverseArgs<double>&)` | 3.64% |
| 4 | `TMBad::global::subgraph_cache_ptr() const` | 2.91% |
| 5 | `TMBad::ADFun<TMBad::global::ad_aug>::Jacobian(std::__1::vector<double, std::__1::allocator<double>> const&, std::__1::vector<double, std::__1::allocator<double>> const&)` | 2.72% |
| 6 | `std::__1::pair<unsigned long long*, bool> std::__1::__partition_with_equals_on_right[abi:ne190102]<std::__1::_ClassicAlgPolicy, unsigned long long*, std::__1::ranges::less>(unsigned long long*, unsigned long long*, std::__1::ranges::less)` | 2.61% |
| 7 | `_platform_memmove` | 2.48% |
| 8 | `Rf_findVarInFrame3` | 2.20% |
| 9 | `TMBad::ADFun<TMBad::global::ad_aug>::operator()(std::__1::vector<double, std::__1::allocator<double>> const&)` | 2.11% |
| 10 | `void radix::radix<unsigned long, unsigned long long>::run_sort<true>()` | 2.10% |
| 11 | `Rf_matchArgs_NR` | 2.08% |
| 12 | `CONS_NR` | 1.72% |
| 13 | `RunGenCollect` | 1.68% |
| 14 | `void radix::radix<unsigned int, unsigned long long>::run_sort<true>()` | 1.53% |
| 15 | `TMBad::global::extract_sub_inplace(std::__1::vector<bool, std::__1::allocator<bool>>)` | 1.46% |
| 16 | `findVarLocInFrame` | 1.43% |
| 17 | `TMBad::global::extract_sub(std::__1::vector<unsigned long long, std::__1::allocator<unsigned long long>>&, TMBad::global)` | 1.42% |
| 18 | `__bzero` | 1.36% |
| 19 | `SETCAR` | 1.35% |
| 20 | `TMBad::global::hash_sweep(TMBad::global::hash_config) const` | 1.31% |
| 21 | `TMBad::global::ad_plain TMBad::global::add_to_stack<TMBad::global::ad_plain::AddOp_<true, true>>(TMBad::global::ad_plain const&, TMBad::global::ad_plain const&)` | 1.18% |
| 22 | `TMBad::global::operation_stack::push_back(TMBad::global::OperatorPure*)` | 1.16% |
| 23 | `TMBad::remap_identical_sub_expressions(TMBad::global&, std::__1::vector<unsigned long long, std::__1::allocator<unsigned long long>>)` | 1.12% |
| 24 | `_platform_strcmp$VARIANT$Base` | 1.00% |
| 25 | `TMBad::global::Complete<TMBad::global::ad_plain::DivOp_<true, true>>::reverse_decr(TMBad::ReverseArgs<double>&)` | 0.98% |
|  | **Top 25 total** | **53.84%** |

#### `dev-native-quadra`

| Rank | Symbol | Samples |
|---:|---|---:|
| 1 | `quadra::CompactFirstOrderTape::Evaluate(Eigen::Matrix<double, -1, 1, 0, -1, 1> const&, Eigen::Matrix<double, -1, 1, 0, -1, 1>&)` | 36.22% |
| 2 | `quadra::CompactFirstOrderTape::Forward()` | 21.52% |
| 3 | `bcEval_loop` | 5.09% |
| 4 | `Rf_findVarInFrame3` | 1.76% |
| 5 | `Rf_matchArgs_NR` | 1.71% |
| 6 | `exp` | 1.58% |
| 7 | `findVarLocInFrame` | 1.38% |
| 8 | `RunGenCollect` | 1.31% |
| 9 | `CONS_NR` | 1.21% |
| 10 | `SETCAR` | 1.18% |
| 11 | `Rf_eval` | 0.81% |
| 12 | `CAR` | 0.77% |
| 13 | `Rf_cons` | 0.75% |
| 14 | `_platform_strcmp$VARIANT$Base` | 0.72% |
| 15 | `setup_vcache` | 0.67% |
| 16 | `Rf_protect` | 0.66% |
| 17 | `SET_TAG` | 0.64% |
| 18 | `Rf_allocVector3` | 0.63% |
| 19 | `__bzero` | 0.63% |
| 20 | `Rf_findFun3` | 0.55% |
| 21 | `R_HashGet` | 0.51% |
| 22 | `log` | 0.49% |
| 23 | `Rf_mkPROMISE` | 0.44% |
| 24 | `Rf_length` | 0.42% |
| 25 | `DYLD-STUB$$exp` | 0.41% |
|  | **Top 25 total** | **82.06%** |

### Interpretation notes

- Sampling identifies where CPU time is spent without tracing every function call.
- Compare hot-symbol rankings across refs; small percentage changes can be sampling noise.
- Open `.trace` files in Instruments or `perf.data` with perf for full call trees.

## Memory profile

Source report: [macos_memory_report.md](macos_memory_report.md)


Generated: `2026-08-25T00:25:08+00:00`
Host: `macOS 15.7.7 (arm64)`
Profilers: Instruments Allocations and `/usr/bin/time -l`

### Summary

macOS reports process-level physical memory rather than Massif's allocated heap. Maximum resident set size (RSS) is the primary comparison metric; peak memory footprint is also shown when the host provides it.

| Git ref | FIMS version | Maximum RSS | Peak footprint | Elapsed | Instruments |
|---|---:|---:|---:|---:|---|
| main | 0.10.0.9000 | **4.96 GiB** | 2.99 GiB | 14.99 s | captured |
| dev-native-quadra | 0.10.0.9000 | **489.28 MiB** | 382.49 MiB | 6.44 s | captured |

### Detailed branch comparison

`dev-native-quadra` used **4.48 GiB less maximum RSS** than `main` (-90.37%).

Positive deltas mean the comparison ref used more of that metric; negative deltas mean less.

| Metric | `main` | `dev-native-quadra` | Delta | Change |
|---|---:|---:|---:|---:|
| Maximum RSS | 4.96 GiB | 489.28 MiB | −4.48 GiB | -90.37% |
| Peak footprint | 2.99 GiB | 382.49 MiB | −2.62 GiB | -87.51% |
| Elapsed time | 14.99 s | 6.44 s | -8.55 s | -57.04% |
| User CPU time | 13.74 s | 6.35 s | -7.39 s | -53.78% |
| System CPU time | 1.08 s | 0.07 s | -1.01 s | -93.52% |
| Page reclaims | 546,868 | 35,203 | -511,665 | -93.56% |
| Page faults | 62 | 24 | -38 | -61.29% |
| Swaps | 0 | 0 | +0 | 0.00% |

#### Interpretation

- Maximum RSS decreased by 4.48 GiB (-90.37%), from 4.96 GiB to 489.28 MiB.
- Peak memory footprint decreased by 2.62 GiB (-87.51%), from 2.99 GiB to 382.49 MiB.
- Elapsed time decreased by 8.55 s (-57.04%), from 14.99 s to 6.44 s.
- Page faults decreased by 38 (-61.29%), from 62 to 24.

#### Instruments allocation totals

Persistent bytes were still allocated at the end of the recording; transient bytes were allocated and freed during the recorded interval.

| Metric | `main` | `dev-native-quadra` | Delta | Change |
|---|---:|---:|---:|---:|
| Persistent bytes | 2.41 GiB | 219.62 MiB | −2.19 GiB | -91.10% |
| Transient bytes | 18.44 GiB | 632.54 MiB | −17.82 GiB | -96.65% |
| Total recorded bytes | 20.85 GiB | 852.16 MiB | −20.01 GiB | -96.01% |
| Persistent allocations | 62,594 | 46,092 | -16,502 | -26.36% |
| Transient allocations | 1,185,792 | 461,807 | -723,985 | -61.05% |
| Total allocations | 1,248,386 | 507,899 | -740,487 | -59.32% |
| Allocation events | 2,431,891 | 969,622 | -1,462,269 | -60.13% |

- Persistent allocated memory decreased by 2.19 GiB (-91.10%), from 2.41 GiB to 219.62 MiB.
- Transient allocated memory decreased by 17.82 GiB (-96.65%), from 18.44 GiB to 632.54 MiB.
- Allocation events decreased by 1,462,269 (-60.13%), from 2,431,891 to 969,622.

#### Largest persistent-allocation category changes

| Category | `main` | `dev-native-quadra` | Delta | Change |
|---|---:|---:|---:|---:|
| VM: MALLOC_LARGE | 5.32 GiB | 165.02 MiB | −5.16 GiB | -96.97% |
| Malloc 512.00 MiB | 1.00 GiB | 0 B | −1.00 GiB | -100.00% |
| Malloc 340.67 MiB | 681.34 MiB | 0 B | −681.34 MiB | -100.00% |
| Malloc 256.00 MiB | 256.00 MiB | 0 B | −256.00 MiB | -100.00% |
| VM: MALLOC_MEDIUM | 640.00 MiB | 384.00 MiB | −256.00 MiB | -40.00% |
| Malloc 182.28 MiB | 182.28 MiB | 0 B | −182.28 MiB | -100.00% |
| Malloc 8.00 KiB | 231.32 MiB | 179.41 MiB | −51.91 MiB | -22.44% |
| VM: MALLOC_SMALL | 264.00 MiB | 216.00 MiB | −48.00 MiB | -18.18% |
| Malloc 2.69 MiB | 8.06 MiB | 0 B | −8.06 MiB | -100.00% |
| Malloc 4.00 MiB | 8.00 MiB | 0 B | −8.00 MiB | -100.00% |

#### Persistent allocation origins

Instruments attributes allocations still live at the end of each recording to the most specific exported responsible symbol. Generic C++ allocations in `FIMS.so` are kept separate when the export does not identify the backend.

| Origin | `main` bytes | Share | `dev-native-quadra` bytes | Share |
|---|---:|---:|---:|---:|
| TMB/TMBad | 801.38 MiB | 32.49% | 4.84 KiB | 0.00% |
| Quadra | 0 B | 0.00% | 2.52 KiB | 0.00% |
| Rcpp | 204.03 KiB | 0.01% | 0 B | 0.00% |
| R runtime | 236.50 MiB | 9.59% | 175.72 MiB | 80.01% |
| FIMS C++ (backend not explicit) | 1.35 GiB | 56.07% | 39.67 KiB | 0.02% |
| System/other/unresolved | 45.46 MiB | 1.84% | 43.85 MiB | 19.96% |

### Run details

#### `main` (FIMS 0.10.0.9000)

| Metric | Value |
|---|---:|
| Maximum resident set size | 4.96 GiB |
| Peak memory footprint | 2.99 GiB |
| Elapsed time | 14.99 s |
| User CPU time | 13.74 s |
| System CPU time | 1.08 s |
| Page reclaims | 546,868 |
| Page faults | 62 |
| Swaps | 0 |

Raw profile: [macos_profile_main_0.10.0.9000.txt](macos_profile_main_0.10.0.9000.txt)

Instruments trace: [instruments_allocations_main_0.10.0.9000.trace](instruments_allocations_main_0.10.0.9000.trace)
Trace table of contents: [instruments_allocations_main_0.10.0.9000_toc.xml](instruments_allocations_main_0.10.0.9000_toc.xml)
Allocation statistics: [instruments_allocations_main_0.10.0.9000_statistics.xml](instruments_allocations_main_0.10.0.9000_statistics.xml)
Allocation origins: [instruments_allocations_main_0.10.0.9000_allocations.xml](instruments_allocations_main_0.10.0.9000_allocations.xml)
Instruments log: [instruments_allocations_main_0.10.0.9000.log](instruments_allocations_main_0.10.0.9000.log)

Open the `.trace` bundle in Instruments to inspect allocation lifetimes, persistent versus transient allocations, types, and recorded stack traces.

#### `dev-native-quadra` (FIMS 0.10.0.9000)

| Metric | Value |
|---|---:|
| Maximum resident set size | 489.28 MiB |
| Peak memory footprint | 382.49 MiB |
| Elapsed time | 6.44 s |
| User CPU time | 6.35 s |
| System CPU time | 0.07 s |
| Page reclaims | 35,203 |
| Page faults | 24 |
| Swaps | 0 |

Raw profile: [macos_profile_dev-native-quadra_0.10.0.9000.txt](macos_profile_dev-native-quadra_0.10.0.9000.txt)

Instruments trace: [instruments_allocations_dev-native-quadra_0.10.0.9000.trace](instruments_allocations_dev-native-quadra_0.10.0.9000.trace)
Trace table of contents: [instruments_allocations_dev-native-quadra_0.10.0.9000_toc.xml](instruments_allocations_dev-native-quadra_0.10.0.9000_toc.xml)
Allocation statistics: [instruments_allocations_dev-native-quadra_0.10.0.9000_statistics.xml](instruments_allocations_dev-native-quadra_0.10.0.9000_statistics.xml)
Allocation origins: [instruments_allocations_dev-native-quadra_0.10.0.9000_allocations.xml](instruments_allocations_dev-native-quadra_0.10.0.9000_allocations.xml)
Instruments log: [instruments_allocations_dev-native-quadra_0.10.0.9000.log](instruments_allocations_dev-native-quadra_0.10.0.9000.log)

Open the `.trace` bundle in Instruments to inspect allocation lifetimes, persistent versus transient allocations, types, and recorded stack traces.

### Interpretation notes

- Compare runs only when both refs use the same model, inputs, and benchmark stage.
- Maximum RSS includes resident code and mapped pages, so it is broader than Massif heap usage.
- Peak footprint is Apple's accounting of the process's physical-memory impact and may be lower than RSS.
- Instruments and the RSS profiler execute the model separately to avoid profiling the Instruments launcher itself.
- The `.trace` bundle is the authoritative detailed allocation record; exported XML is provided for automation.
- macOS and Massif results should be compared within their own profiler type, not directly across operating systems.
