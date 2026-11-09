# Prediksi luaran hantavirus dengan regresi logistik

[Read in English](README.md)

Analisis ini memakai regresi logistik untuk memperkirakan peluang sembuh pada luaran hantavirus biner. Evaluasi membandingkan bagaimana ambang klasifikasi mengubah jumlah kasus meninggal yang terlewat dan pasien sembuh yang ikut ditandai.

[Semua 26 grafik (PDF)](visualisasi_hantavirus.pdf) · [Grafik satu per satu (ZIP PNG)](visualisasi_hantavirus_png.zip)

## Data dan preprocessing

Analisis ini memakai [`hantavirus_clinical.xlsx`](hantavirus_clinical.xlsx). Sumber datanya adalah [Hantavirus (Andes Virus) — Global Epidemiology](https://www.kaggle.com/datasets/zkskhurram/hantavirus-andes-virus-global-epidemiology) yang diunggah oleh `zkskhurram` di Kaggle.

Workbook berisi 10.000 ID pasien unik. Di workbook ini, `outcome_biner = 1` berarti Sembuh dan `0` berarti Meninggal. Grafik mempertahankan label `Meninggal/Buruk` dari laporan asal.

| Split | Sembuh | Meninggal | Total |
| --- | ---: | ---: | ---: |
| Training | 7.150 | 849 | 7.999 |
| Testing | 1.788 | 213 | 2.001 |

1. Skrip memeriksa kolom wajib, mengonversi lima prediktor numerik, dan memvalidasi outcome 0/1 serta ID pasien. Seluruh 10.000 baris lolos pemeriksaan outcome dan ID. Split terstratifikasi dengan seed 123 memasukkan sekitar 80% anggota tiap kelas ke training.
2. Skrip menggunakan training untuk menentukan level faktor, kelompok kategori langka, dan aturan imputasi. Level dengan kurang dari 25 observasi training digabung untuk `country`, `comorbidity`, `exposure_type`, dan `treatment_protocol`. Hanya `MV Hondius (International)` yang masuk kelompok langka, mencakup 10 baris training dan 3 baris testing.
3. Jika ada nilai kosong, skrip memakai median training untuk prediktor numerik dan modus training untuk prediktor kategorik. Level yang baru muncul di testing masuk kelompok langka training jika tersedia, atau memakai modus training. Workbook ini mencatat nol imputasi dan nol level baru.
4. Skrip menyaring prediktor konstan atau kolinear berdasarkan training. Tiap kategori negara di training hanya memuat satu jenis sindrom, sehingga skrip mempertahankan `syndrome` dan mengeluarkan `country` dari kandidat model. Jumlah gejala dan lama rawat masuk analisis deskriptif dan diagnostik. Uji Box-Tidwell menemukan indikasi nonlinier untuk keduanya. Pergeseran satu hari pada lama rawat hanya berlaku dalam uji tersebut.

### Temuan dari grafik training

| Grafik | Temuan pada training |
| --- | --- |
| Outcome, sindrom, keparahan | Sebanyak 89,4% pasien tercatat sembuh. HFRS mencakup 5.189 pasien dan HPS 2.810 pasien. Tingkat Moderate paling banyak (2.592), disusul Severe (2.286), Mild (2.018), dan Critical (1.103). |
| Negara, jenis kelamin, golongan darah, lokasi, paparan | Korea Selatan adalah kategori negara terbanyak (692). Terdapat 4.903 pasien laki-laki. O+ (3.157), lokasi rural (3.961), dan paparan rural dwelling (1.832) paling banyak dalam grafik masing-masing. |
| Komorbiditas dan viral load | Kategori komorbiditas None paling banyak (3.154) dan kategori viral load High paling banyak (2.550). |
| Rawat inap, ICU, ventilasi, ECMO, dialisis, protokol | Grafik mencatat 6.578 rawat inap, 2.357 masuk ICU, 671 ventilasi mekanik, 278 penggunaan ECMO, dan 654 dialisis. Cairan IV dengan oksigen adalah protokol terbanyak (2.630). Grafik batang ini merangkum frekuensi dalam workbook. |
| Boxplot numerik dan scatter plot inkubasi terhadap lama rawat | Sebaran usia, masa inkubasi, dan waktu ke diagnosis banyak bertumpang tindih. Median lama rawat adalah 11 hari pada kelompok meninggal dan 8 hari pada kelompok sembuh. Beberapa pasien memiliki pasangan hari yang sama sehingga titik pada scatter plot saling menutupi. |

## Pemilihan dan interpretasi model

Keempat model regresi logistik dilatih pada 7.999 baris yang sama. Akaike information criterion (AIC) mempertimbangkan kecocokan model dan jumlah parameternya.

| Model pada training | Prediktor | Parameter | AIC |
| --- | ---: | ---: | ---: |
| Full | 17 | 51 | 3978,95 |
| Forward | 2 | 5 | 3926,78 |
| Backward | 2 | 5 | 3926,78 |
| Stepwise | 2 | 5 | 3926,78 |

Forward, backward, dan stepwise menghasilkan formula yang sama, `outcome_biner ~ severity + syndrome`. Skrip mencatat Stepwise sesuai urutan yang ditetapkan saat hasilnya seri. Deviance training turun dari 5413,16 pada model intersep saja menjadi 3916,78 pada model terpilih. Pseudo-R² McFadden sebesar 0,2764.

| Perbandingan setelah penyesuaian | Odds ratio Sembuh | Interval Wald 95% |
| --- | ---: | ---: |
| Mild dibanding Critical | 28,89 | 19,87 sampai 42,00 |
| Moderate dibanding Critical | 24,94 | 18,59 sampai 33,47 |
| Severe dibanding Critical | 3,71 | 3,11 sampai 4,42 |
| HPS dibanding HFRS | 0,22 | 0,19 sampai 0,26 |

Grafik odds ratio memakai skala log dengan garis referensi di 1. Pada tingkat keparahan yang sama, model memperkirakan odds sembuh lebih rendah untuk HPS daripada HFRS. Pada sindrom yang sama, Mild, Moderate, dan Severe memiliki estimasi odds sembuh lebih tinggi daripada Critical. Interval Wald bersifat eksploratif karena dihitung setelah seleksi prediktor.

## Kinerja testing pada kelas tidak seimbang

![Kurva ROC training dan testing. Kedua penanda menggunakan ambang Youden yang dihitung dari training.](figures/evaluasi_roc.png)

| Metrik testing lintas ambang | Positif Sembuh | Positif Meninggal |
| --- | ---: | ---: |
| AUC ROC | 0,8654 | 0,8654 |
| PR-AUC (integral PRROC) | 0,9803 | 0,4361 |
| Average precision | 0,9764 | 0,4111 |
| Baseline precision-recall (prevalensi) | 0,8936 | 0,1064 |

AUC ROC training adalah 0,8574 dan AUC ROC testing adalah 0,8654 (CI 95% 0,8421 sampai 0,8887). Kurva precision-recall yang dilampirkan memakai Sembuh sebagai kelas positif, sehingga baseline-nya sekitar 0,894. Perhitungan ulang dengan `P(Meninggal) = 1 - P(Sembuh)` menilai pengurutan kelas minoritas secara langsung. Average precision dan PR-AUC memakai cara integrasi yang berbeda.

Model menghasilkan delapan skor dari kombinasi empat tingkat keparahan dan dua jenis sindrom. Grafik distribusi yang dihaluskan menunjukkan tumpang tindih skor di sekitar ambang Youden. Tiga interval kalibrasi yang terisi berada dekat garis diagonal, dengan 160, 358, dan 1.483 baris testing. Brier score adalah 0,0711, dibandingkan dengan 0,0951 jika semua pasien testing diberi skor sebesar proporsi sembuh di training.

## Pemilihan ambang klasifikasi

Model memprediksi Sembuh jika `P(Sembuh) >= ambang`. Menaikkan ambang membuat lebih banyak pasien ditandai Meninggal/Buruk. Skrip memaksimalkan indeks Youden (sensitivitas + spesifisitas - 1) pada skor training, lalu memakai nilai persisnya, sekitar 0,9321, pada testing. Karena kelas positif pada output asal adalah Sembuh, **specificity sama dengan recall kasus meninggal**.

![Confusion matrix testing untuk ambang 0,50 dan Youden training. Persentase dihitung dalam tiap kelas aktual.](figures/testing_confusion_matrix.png)

| Metrik testing | Ambang 0,50 | Youden training |
| --- | ---: | ---: |
| Meninggal terdeteksi / terlewat | 91 / 122 | 169 / 44 |
| Pasien sembuh ditandai Meninggal/Buruk | 69 | 349 |
| Precision Meninggal | 56,9% | 32,6% |
| Recall Meninggal | 42,7% | 79,3% |
| F1 Meninggal | 0,488 | 0,462 |
| Precision Sembuh | 93,4% | 97,0% |
| Recall Sembuh | 96,1% | 80,5% |
| F1 Sembuh | 0,947 | 0,880 |
| Macro F1 | 0,718 | 0,671 |
| Weighted F1 | 0,898 | 0,835 |
| Balanced accuracy | 69,4% | 79,9% |
| Matthews correlation coefficient (MCC) | 0,442 | 0,421 |
| Akurasi | 90,5% | 80,4% |

F1 menggabungkan precision dan recall. Macro F1 memberi bobot sama pada tiap kelas, weighted F1 memakai ukuran kelas sebagai bobot, dan balanced accuracy merata-ratakan recall kedua kelas. MCC merangkum empat sel confusion matrix. Prediksi Sembuh untuk semua pasien akan menghasilkan akurasi 89,4%, balanced accuracy 50,0%, dan F1 Meninggal 0.

Dari kedua ambang yang diuji, **pilih Youden jika prioritasnya menangkap lebih banyak kasus meninggal**. Ambang ini mendeteksi 78 kematian tambahan dan menandai 280 pasien sembuh tambahan. Ambang 0,50 memberi F1 Meninggal, macro F1, dan MCC lebih tinggi pada perbandingan ini. Ambang 1,00 mencapai nol kematian terlewat dengan menandai seluruh 2.001 pasien, termasuk 1.788 yang sembuh. Salah satu pasien yang meninggal mendapat skor P(Sembuh) tertinggi, sekitar 0,9907.

Angka ini mengukur performa pada split acak di workbook yang sama. Evaluasi di tempat lain memerlukan kelompok pasien terpisah dan waktu prediksi yang ditetapkan, saat informasi keparahan sudah tersedia.

## Menjalankan ulang analisis

Analisis dijalankan di R 4.4.3. Instal paket melalui R, lalu jalankan skrip dari folder repositori dengan salinan workbook lokal.

```r
install.packages(c("readxl", "ggplot2", "scales", "car", "caret", "pROC", "PRROC"))
```

```powershell
Rscript .\hantavirus_outcome.R "C:\lokasi\hantavirus_clinical.xlsx"
```

Di RStudio, buka [skrip R](hantavirus_outcome.R), klik **Source**, lalu jalankan `hasil <- run_hantavirus(file.choose())`. Pakai `hasil$threshold_youden` untuk ambang presisi penuh. Skrip mencetak metrik testing dan menyimpan `hantavirus_plots.pdf` serta `hantavirus_plots_png/` di direktori kerja R.

[Laporan RPubs asal](https://rpubs.com/rayyanonrpubs/hantavirusoutcome) · [Audit teknis](anti-slop/audit-001-2026-11-09.md)
