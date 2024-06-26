library(rpact)
library(tidyverse)
library(glue)

# Trial Design Parameters - Part 1
# Here we will specify the basics: maximum total number of patients to enroll and event rate for each treatment arm
nPatients <- 1000 # here is where you specify the planned max number of patients you want included in each RCT 
death0 <- 0.4 # here is where you specify the event rate for patients receiving 'treatment 0' in these trials
death1 <- 0.4 # here is where you specify the event rate for patients receiving 'treatment 1' in these trials
# I have set this one up to test the power for a treatment that would reduce mortality from 40% in control group (0) to 30% in treatment group (1)
# If one wants to estimate the "type 1 error" under different interim approaches, simply make 'death0' and 'death1' the same (no treatment effect)

trueOR <- (death1/(1-death1))/(death0/(1-death0))

# Trial Design Parameters - Part 2
# Here we will define the interim analysis strategy and stopping rules
# For this trial we will include provisions for efficacy stopping only (no futility stopping boundaries)
# We will use the rpact package to compute the stopping/success thresholds at interim and final analysis 
# install.packages("rpact")

nLooks<-5 # here is where you put the number of looks that will take place (INCLUDING the final analysis)
analyses_scheduled <- seq(from = 1/nLooks, to = 1, by = 1/nLooks) # here is where you list the information fraction (e.g. 50%, 75% and 100% information)
efficacy_thresholds <- numeric(nLooks)

design <- getDesignGroupSequential(sided=1, alpha=0.05, informationRates=analyses_scheduled, typeOfDesign = "asOF")

for(j in 1:nLooks){ #get the alpha for each look
efficacy_thresholds[j] = design$stageLevels[j]
}

analyses_nPatients <- analyses_scheduled*nPatients

analyses_scheduled
analyses_nPatients
efficacy_thresholds

# Simulation Parameters
nSims <- 20
trialnum <- numeric(nSims)
or <- data.frame(matrix(ncol = nLooks, nrow = nSims))
lcl <- data.frame(matrix(ncol = nLooks, nrow = nSims))
ucl <- data.frame(matrix(ncol = nLooks, nrow = nSims))
pvalue <- data.frame(matrix(ncol = nLooks, nrow = nSims))
success <- data.frame(matrix(ncol = nLooks, nrow = nSims))
zvalue <- data.frame(matrix(ncol = nLooks, nrow = nSims))

#provide column names
colnames(or) <- sprintf("or_%d", (1:nLooks))
colnames(lcl) <- sprintf("lcl_%d", (1:nLooks))
colnames(ucl) <- sprintf("ucl_%d", (1:nLooks))
colnames(zvalue) <- sprintf("zvalue_%d", (1:nLooks))
colnames(pvalue) <- sprintf("pvalue_%d", (1:nLooks))
colnames(success) <- sprintf("success_%d", (1:nLooks))

overall_success <- numeric(nSims)


# Simulation --------------------------------------------------------------
set.seed(201) # this sets the random seed for your results to be reproducible

for(i in 1:nSims) {
  trialnum[i] = i
  
  pid = seq(1, by = 1, len = nPatients)
  treatment = rep(0:1, nPatients / 2)
  deathprob <- numeric(nPatients)
  deathprob[treatment == 0] = death0
  deathprob[treatment == 1] = death1
  death = rbinom(nPatients, 1, deathprob)
  trialdata = data.frame(cbind(pid, treatment, death))
  
  for (j in 1:nLooks) {
    analysisdata <- subset(trialdata, pid <= analyses_nPatients[j])
    
    model <- glm(death ~ treatment,
              family = binomial(link = 'logit'),
              data = analysisdata)
    
    or[i, j] = round(exp(summary(model)$coefficients[2]), digits = 2)
    
    lcl[i, j] = round(exp(
      summary(model)$coefficients[2] - 1.96 * summary(model)$coefficients[4]
    ), digits = 2)
    
    ucl[i, j] = round(exp(
      summary(model)$coefficients[2] + 1.96 * summary(model)$coefficients[4]
    ), digits = 2)
    
    pvalue[i, j] = round(summary(model)$coefficients[8], digits = 4)
    
    zvalue[i, j] = round(summary(model)$coefficients[6], digits = 4)
    
    success[i, j] = ifelse(or[i, j] < 1 &
                             pvalue[i, j] < efficacy_thresholds[j], 1, 0)
  }
  
  overall_success[i] <- 0
  
  for (j in 1:nLooks)
  {
    if (success[i, j] == 1)
    {
      overall_success[i] <- 1
    }
  }
  
}

#Build dataframe (wide format)
simulation_results <- tibble(trialnum)

for(i in 1:nLooks){
  new_columns <- tibble(
    or[i],
    lcl[i],
    ucl[i],
    zvalue[i],
    pvalue[i],
    success[i]
  )
  
  simulation_results <- bind_cols(simulation_results, new_columns)
}

simulation_results <- bind_cols(simulation_results, tibble(overall_success))

simulation_results <- simulation_results %>%
  mutate("or_{i}" := or[i],
         "lcl_{i}" := lcl[i],
         "ucl_{i}" := ucl[i],
         "zvalue_{i}" := zvalue[i],
         "pvalue_{i}" := pvalue[i],
         "sucess_{i}" := success[i]
  )

#table(overall_success)
#table(simulation_results$success_1, overall_success)
#table(simulation_results$success_2, overall_success)
#table(simulation_results$success_3, overall_success)
#table(simulation_results$success_4, overall_success)
#table(simulation_results$success_5, overall_success)


# Data wrangling / conversion to long format ------------------------------
# Custom function to convert to long format
convert_to_long <- function(data, prefix) {
  data %>%
    mutate(trial = row_number()) %>%
    pivot_longer(
      cols = starts_with(prefix), 
      names_to = c("look"), 
      values_to = paste(prefix)
    ) %>%
    mutate(look = as.numeric(gsub(paste0(prefix, "_"), "", look)))
}

#apply function
or_long <- convert_to_long(or, "or")
zvalue_long <- convert_to_long(zvalue, "zvalue")
pvalue_long <- convert_to_long(pvalue, "pvalue")
success_long <- convert_to_long(success, "success")

overall_success_long <- tibble(overall_success = as.factor(rep(overall_success, each = nLooks)))

#create one df_long
df_long <- suppressMessages(right_join(or_long, zvalue_long))
df_long <- suppressMessages(right_join(df_long, pvalue_long))
df_long <- suppressMessages(right_join(df_long, success_long))
df_long <- df_long %>% bind_cols(overall_success_long)
df_not_stopped_interim <- df_long %>% bind_cols(tibble(nPat = rep(NA, nLooks*nSims)))

for(i in 1:nLooks){
  df_not_stopped_interim <- df_not_stopped_interim %>%
    mutate(
      nPat = case_when(
        look == i ~ analyses_nPatients[i], 
        look != i ~ nPat
      )
    )
}


  df_not_stopped_interim <- df_not_stopped_interim %>%
    group_by(trial) %>%
    mutate(first_success_index = min(which(success == 1))) %>%
    mutate(first_success_index = ifelse(first_success_index == Inf, nLooks, first_success_index))  %>%
    ungroup() %>%
    mutate(first_success_index = ifelse(overall_success == 0, "Never", first_success_index)) %>%
    arrange(first_success_index) %>%
    mutate(first_success_index = factor(first_success_index)) %>%
    arrange(trial, look)

#create dataframe which simulates trial stop if interim results sign
df_stopped_interim <- df_long %>%
  group_by(trial) %>%
  mutate(first_success_index = min(which(success == 1))) %>%
  mutate(first_success_index = ifelse(first_success_index == Inf, nLooks, first_success_index))  %>%
  ungroup() %>%
  filter(look <= first_success_index) %>%
  mutate(first_success_index = ifelse(overall_success == 0, "Never", first_success_index)) %>%
  arrange(first_success_index) %>%
  mutate(first_success_index = factor(first_success_index)) %>%
  arrange(trial, look)


#create table with the critical z values
df_critical_z <- tibble(zvalue = qnorm(efficacy_thresholds/2), nPat = analyses_nPatients)

#remove no longer needed objects
#rm(i, j, death, deathprob, efficacy_thresholds, pid, treatment, trialnum, overall_success, lcl, model, new_columns, or, or_long, overall_success_long, pvalue, pvalue_long, success, simulation_results, success_long, trialdata, ucl, zvalue, zvalue_long)