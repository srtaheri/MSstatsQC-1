getMetricData <- function(data, peptide, L, U, metric, normalization, selectMean, selectSD) {
  #"Precursor" is one of the columns in data that shows the name of peptides
  precursor.data<-data[data$Precursor==peptide,]
  metricData <- 0
  mu <- 0
  sd <- 0

  if(is.null(metric)){
    return(NULL)
  }

  metricData = precursor.data[,metric]

  if(normalization == TRUE) {
    if(is.null(selectMean) && is.null(selectSD)) {
      mu=mean(metricData[L:U]) # in-control process mean
      sd=sd(metricData[L:U]) # in-control process variance
    }else {
      mu = selectMean
      sd = selectSD
    }

    if(sd == 0) {sd <- 0.0001}
    metricData=scale(metricData[seq_along(metricData)],mu,sd) # transformation for N(0,1) )
    return(metricData)
  } else if(normalization == FALSE){
    return(metricData)
  }

}

#########################################################################################################
find_custom_metrics <- function(data) {

  data <- data[, which(colnames(data)=="Annotations"):ncol(data),drop = FALSE]
  nums <- sapply(data, is.numeric)

  other.metrics <- colnames(data[,nums])[seq_len(ifelse(length(colnames(data[,nums]))<11,
                                                        length(colnames(data[,nums])),
                                                        10))]
  if(any(is.na(other.metrics))) {
    return(c())
  }
  return(other.metrics)
}
################################################################
CUSUM.data.prepare <- function(data, metricData, peptide, type, referenceValue, decisionInterval) {
  k <- referenceValue
  CUSUM.outrange.thld <- decisionInterval
  outRangeInRangePoz <- rep(0,length(metricData))
  outRangeInRangeNeg <- rep(0,length(metricData))
  precursor.data <- data[data$Precursor==peptide,]

  v <- numeric(length(metricData))

  Cpoz <- numeric(length(metricData))
  Cneg <- numeric(length(metricData))

  for(i in 2:length(metricData)) {
    Cpoz[i] <- max(0,(metricData[i]-(k)+Cpoz[i-1]))
    Cneg[i] <- max(0,((-k)-metricData[i]+Cneg[i-1]))
  }

  if(type == "variability") {
    for(i in 2:length(metricData)) {
      v[i] <- (sqrt(abs(metricData[i]))-0.822)/0.349
    }
    for(i in 2:length(metricData)) {
      Cpoz[i] <- max(0,(v[i]-(k)+Cpoz[i-1]))
      Cneg[i] <- max(0,((-k)-v[i]+Cneg[i-1]))
    }
  }

  QCno <- seq_along(metricData)

  for(i in seq_along(metricData)) {
    if(Cpoz[i] >= CUSUM.outrange.thld || Cpoz[i] <= -CUSUM.outrange.thld)
      outRangeInRangePoz[i] <- "OutRangeCUSUM+"
    else
      outRangeInRangePoz[i] <- "InRangeCUSUM+"
  }

  for(i in seq_along(metricData)) {
    if(-Cneg[i] >= CUSUM.outrange.thld || -Cneg[i] <= -CUSUM.outrange.thld)
      outRangeInRangeNeg[i] <- "OutRangeCUSUM-"
    else
      outRangeInRangeNeg[i] <- "InRangeCUSUM-"
  }

  plot.data <- data.frame(QCno = QCno
               ,CUSUM.poz = Cpoz
               ,CUSUM.neg = -Cneg
               ,Annotations=precursor.data$Annotations
               ,outRangeInRangePoz = outRangeInRangePoz
               ,outRangeInRangeNeg = outRangeInRangeNeg
    )

  return(plot.data)
}
###################################################################################################

CP.data.prepare <- function(metricData, type) {

  Et <-  numeric(length(metricData)-1) # this is Ct in type = mean , and Dt in type = variability.
  SS <- numeric(length(metricData)-1)
  SST <- numeric(length(metricData)-1)
  tho.hat <- 0

  if(type == "mean") {

    for(i in seq_len(length(metricData)-1)) {
      Et[i]=(length(metricData)-i)*
        (((1/(length(metricData)-i))*
            sum(metricData[(i+1):length(metricData)]))-0)^2 #change point function
    }

    QCno <- seq_len(length(metricData)-1)}

    else if(type == "variability") {

    for(i in seq_along(metricData)) {
      SS[i] <- metricData[i]^2
    }

    for(i in seq_along(metricData)) {

      SST[i] <- sum(SS[seq_along(metricData)])

      Et[i] <- ((SST[i]/2)-((length(metricData)-i+1)/2)*
               log(SST[i]/(length(metricData)-i+1))-(length(metricData)-i+1)/2)
    }

    QCno <- seq_along(metricData)
  }
  tho.hat <- which(Et==max(Et))
  plot.data <- data.frame(QCno,Et,tho.hat)

  return(plot.data)
}
###################################################################################################
get_CP_tho.hat <- function(data, L, U, data.metrics, listMean, listSD) {
  tho.hat <- data.frame(tho.hat = c(), metric = c(), group = c(), y=c())
  precursors <- levels(data$Precursor)
  for(metric in data.metrics) {

    for (j in seq_len(nlevels(data$Precursor))) {
      metricData <- getMetricData(data, precursors[j], L, U, metric = metric,normalization = TRUE,
                                  selectMean = listMean[[metric]],selectSD = listSD[[metric]])
      mix <- rbind(
        data.frame(tho.hat = CP.data.prepare(metricData, type = "mean")$tho.hat[1],
                   metric = metric, group = "Individual Value", y=1.1),
        data.frame(tho.hat = CP.data.prepare(metricData, type = "variability")$tho.hat[1],
                   metric = metric, group = "Moving Range", y=-1.1)
      )
      tho.hat <- rbind(tho.hat, mix)

    }
  }

  return(tho.hat)
}
###################################################################################################

XmR.data.prepare <- function(metricData, L, U, type, selectMean, selectSD) {
  t <- numeric(length(metricData)-1)
  UCL <- 0
  LCL <- 0
  InRangeOutRange <- rep(0,length(metricData))

  for(i in 2:length(metricData)) {
    t[i] <- abs(metricData[i]-metricData[i-1])
  }

  QCno <- seq_along(metricData)

  if(type == "mean") {
    if(is.null(selectMean) && is.null(selectSD)) {
      UCL=mean(metricData[L:U])+2.66*sd(t[L:U])
      LCL=mean(metricData[L:U])-2.66*sd(t[L:U])
    }else {
      UCL = selectMean + 2.66 * selectSD
      LCL = selectMean - 2.66 * selectSD
    }
    t <- metricData
  }else if(type == "variability") {

    if(is.null(selectMean) && is.null(selectSD)) {
      UCL=3.267*sd(t[1:L-U])
    }else{
      UCL = 3.267 * selectSD
    }
    LCL=0
  }

  for(i in seq_along(metricData)) {
    if(t[i] > LCL && t[i] < UCL)
      InRangeOutRange[i] <- "InRange"
    else
      InRangeOutRange[i] <- "OutRange"
  }

  plot.data <- data.frame(QCno,IndividualValue=metricData, mR=t, UCL, LCL, InRangeOutRange)
  return(plot.data)
}
############################################################################################

CUSUM.River.prepare <- function(data, metric, L, U,type, selectMean, selectSD, decisionInterval) {
  h <- decisionInterval

  QCno <- seq_len(nrow(data))
  y.poz <- rep(0,nrow(data))
  y.neg <- rep(0,nrow(data))
  counter <- rep(0,nrow(data))

  precursors <- levels(data$Precursor)

  for(j in seq_len(length(precursors))) {
    metricData <- getMetricData(data, precursors[j], L, U, metric = metric,
                                normalization = TRUE, selectMean, selectSD)
    counter[seq_along(metricData)] <- counter[seq_along(metricData)]+1
    plot.data <- CUSUM.data.prepare(data, metricData, precursors[j], type, referenceValue = 0.5, decisionInterval = 5)

    sub.poz <- plot.data[plot.data$CUSUM.poz >= h | plot.data$CUSUM.poz <= -h, ]
    sub.neg <- plot.data[plot.data$CUSUM.neg >= h | plot.data$CUSUM.neg <= -h, ]

    y.poz[sub.poz$QCno] <- y.poz[sub.poz$QCno] + 1
    y.neg[sub.neg$QCno] <- y.neg[sub.neg$QCno] + 1
  }
  max_QCno <- max(which(counter!=0))

  pr.y.poz = y.poz[seq_len(max_QCno)]/counter[seq_len(max_QCno)]
  pr.y.neg = y.neg[seq_len(max_QCno)]/counter[seq_len(max_QCno)]

  plot.data <- data.frame(QCno = rep(seq_len(max_QCno),2),
                          pr.y = c(pr.y.poz, pr.y.neg),
                          group = ifelse(rep(type == "mean",2*max_QCno),
                                         c(rep("Mean increase",max_QCno),
                                           rep("Mean decrease",max_QCno)),
                                         c(rep("Variability increase",max_QCno),
                                           rep("Variability decrease",max_QCno))),
                          metric = rep(metric,max_QCno*2)
  )
  return(plot.data)
}
############################################################################################
CUSUM.River.DataFrame <- function(data, data.metrics, L, U,listMean,listSD) {
  dat <- data.frame(QCno = c(),
                    pr.y = c(),
                    group = c(),
                    metric = c())
  for (metric in data.metrics) {
    data.1   <- CUSUM.River.prepare(data, metric = metric, L, U,type = "mean",
                                      selectMean = listMean[[metric]], selectSD = listSD[[metric]], decisionInterval = 5)
    data.2   <- CUSUM.River.prepare(data, metric = metric, L, U,type = "variability",
                                      selectMean = listMean[[metric]], selectSD = listSD[[metric]], decisionInterval = 5)
    data.2$pr.y <- -(data.2$pr.y)
    dat <- rbind(dat,data.1,data.2)
  }
  return(dat)
}
############################################################################################

XmR.River.prepare <- function(data, metric, L, U,type,selectMean,selectSD) {
  QCno    <- seq_len(nrow(data))
  y.poz <- rep(0,nrow(data))
  y.neg <- rep(0,nrow(data))
  counter <- rep(0,nrow(data))

  precursors <- levels(data$Precursor)

  for(j in seq_len(length(precursors))) {
    metricData <- getMetricData(data, precursors[j], L = L, U = U, metric = metric,
                                normalization = TRUE,selectMean,selectSD)
    counter[seq_along(metricData)] <- counter[seq_along(metricData)]+1
    plot.data <- XmR.data.prepare(metricData , L , U , type,selectMean,selectSD)

    sub.poz <- plot.data[plot.data$t >= plot.data$UCL, ]
    sub.neg <- plot.data[plot.data$t <= plot.data$LCL, ]

    y.poz[sub.poz$QCno] <- y.poz[sub.poz$QCno] + 1
    y.neg[sub.neg$QCno] <- y.neg[sub.neg$QCno] + 1
  }
  max_QCno <- max(which(counter!=0))
  pr.y.poz <- y.poz[1:max_QCno]/counter[1:max_QCno]
  pr.y.neg <- y.neg[1:max_QCno]/counter[1:max_QCno]

  plot.data <- data.frame(QCno = rep(1:max_QCno,2),
                          pr.y = c(pr.y.poz, pr.y.neg),
                          group = ifelse(rep(type == "mean",2*max_QCno),
                                         c(rep("Mean increase",max_QCno),
                                           rep("Mean decrease",max_QCno)),
                                         c(rep("Variability increase",max_QCno),
                                           rep("Variability decrease",max_QCno))),
                          metric = rep(metric,max_QCno*2))

  return(plot.data)
}
###########################################################################################

XmR.River.DataFrame <- function(data, data.metrics, L, U, listMean, listSD) {
  dat <- data.frame(QCno = c(),
                    pr.y = c(),
                    group = c(),
                    metric = c())

  for (metric in data.metrics) {
    data.1   <- XmR.River.prepare(data, metric = metric, L, U,type = "mean",
                                    selectMean = listMean[[metric]],selectSD = listSD[[metric]])
    data.2   <- XmR.River.prepare(data, metric = metric, L, U,type = "variability",
                                    selectMean = listMean[[metric]],selectSD = listSD[[metric]])
    data.2$pr.y <- -(data.2$pr.y)
    dat <- rbind(dat, data.1, data.2)
  }
  return(dat)
}
############################################################################################
heatmap.DataFrame <- function(data, data.metrics, method,
                              peptideThresholdRed, peptideThresholdYellow, L, U,
                              type, listMean, listSD) {

  time <- c()
  val <- c()
  met <- c()
  bin <- c()

  for (metric in data.metrics) {
    df <- Decision.DataFrame.prepare(data, metric, method,
                                     peptideThresholdRed,peptideThresholdYellow,
                                     L, U,type, selectMean = listMean[[metric]],
                                     selectSD=listSD[[metric]])

    time_df <- as.character(df$AcquiredTime)
    val_df <- df$pr.y
    met_df <- rep(metric,length(val_df))
    bin_df <- df$bin
    time <- c(time,time_df)
    val <- c(val,val_df)
    met <- c(met,met_df)
    bin <- c(bin,bin_df)
  }

  dataFrame <- data.frame(time = time,
                          value = val,
                          metric = met,
                          bin = bin
  )
  return(dataFrame)
}
############################################################################################
Compute.QCno.OutOfRangePeptide.XmR <- function(data,L,U,metric,type,
                                               XmR.type,selectMean,selectSD) {
  precursors <- levels(data$Precursor)
  QCno.out.range <- c()

  for(j in seq_len(length(precursors))) {
    metricData <- getMetricData(data, precursors[j], L = L, U = U,
                                metric = metric, normalization = TRUE,selectMean,selectSD)
    plot.data <- XmR.data.prepare(metricData , L = L, U = U, type,selectMean,selectSD)
    if(XmR.type == "poz")
      QCno.out.range <- c(QCno.out.range,length(plot.data[plot.data$t >= plot.data$UCL, ]$QCno))
    else
      QCno.out.range <- c(QCno.out.range,length(plot.data[plot.data$t <= plot.data$LCL, ]$QCno))
  }
  return(QCno.out.range)
}
#############################################################################################
Compute.QCno.OutOfRangePeptide.CUSUM <- function(data, L, U, metric, type, CUSUM.type, selectMean, selectSD) {
  h <- 5
  precursors <- levels(data$Precursor)
  QCno.out.range <- c()

  for(j in seq_len(length(precursors))) {
    metricData <- getMetricData(data, precursors[j], L, U, metric = metric,
                                normalization = TRUE,selectMean,selectSD)
    plot.data <- CUSUM.data.prepare(data, metricData, precursors[j], type, referenceValue = 0.5, decisionInterval = 5)
    if(CUSUM.type == "poz")
      QCno.out.range <- c(QCno.out.range,
                          length(plot.data[plot.data$CUSUM.poz >= h | plot.data$CUSUM.poz <= -h, ]$QCno))
    else
      QCno.out.range <- c(QCno.out.range,
                          length(plot.data[plot.data$CUSUM.neg >= h | plot.data$CUSUM.neg <= -h, ]$QCno))
  }
  return(QCno.out.range)
}
###############################################################################################################
XmR.Radar.Plot.prepare <- function(data, L, U, metric, type, group, XmR.type, selectMean, selectSD) {
  precursors <- levels(data$Precursor)
  precursors2 <- substring(precursors, first = 1, last = 3)
  QCno.length <- c()
  QCno.out.range.poz <- c()
  QCno.out.range.neg <- c()
  for(j in seq_len(length(precursors))) {
    metricData <- getMetricData(data, precursors[j], L = L, U = U,
                                metric = metric, normalization = TRUE,
                                selectMean,selectSD)
    QCno.length <- c(QCno.length,length(metricData))
    plot.data <- XmR.data.prepare( metricData , L = L, U = U,
                                  type ,selectMean,selectSD)
    QCno.out.range.poz <- c(QCno.out.range.poz,
                            length(plot.data[plot.data$t >= plot.data$UCL, ]$QCno))
    QCno.out.range.neg <- c(QCno.out.range.neg,
                            length(plot.data[plot.data$t <= plot.data$LCL, ]$QCno))
  }

  if(XmR.type == "poz") {
    dat <- data.frame(peptides = precursors2,
                      OutRangeQCno  = QCno.out.range.poz,
                      group         = rep(group,length(precursors)),
                      #orderby       = seq(1:length(precursors)),
                      orderby       = seq(seq_along(precursors)),
                      metric        = rep(metric, length(precursors)),
                      tool          = rep("XmR",length(precursors)),
                      probability   = QCno.out.range.poz/QCno.length
    )
  } else {
    dat <- data.frame(peptides = precursors2,
                      OutRangeQCno  = QCno.out.range.neg,
                      group         = rep(group,length(precursors)),
                      #orderby       = seq(1:length(precursors)),
                      orderby       = seq(seq_along(precursors)),
                      metric        = rep(metric, length(precursors)),
                      tool          = rep("XmR",length(precursors)),
                      probability   = QCno.out.range.neg/QCno.length
    )
  }
  return(dat)
}
################################################################################################
XmR.Radar.Plot.DataFrame <- function(data, data.metrics, L, U, listMean, listSD) {
  dat <- data.frame(peptides = c(), OutRangeQCno = c(), group = c(),
                    orderby = c(), metric = c(), tool = c(),
                    probability   = c()
  )
  for (metric in data.metrics) {
    data.1 <- XmR.Radar.Plot.prepare(data,L,U,metric = metric,
                                     type = "mean",group = "Mean increase",
                                     XmR.type = "poz",
                                     selectMean = listMean[[metric]],selectSD = listSD[[metric]])
    data.2 <- XmR.Radar.Plot.prepare(data,L,U,metric = metric,
                                     type = "mean",group = "Mean decrease",
                                     XmR.type = "neg",
                                     selectMean = listMean[[metric]],selectSD = listSD[[metric]])
    data.3 <- XmR.Radar.Plot.prepare(data,L,U,metric = metric,
                                     type = "variability",group = "Variability increase",
                                     XmR.type = "poz",
                                     selectMean = listMean[[metric]],selectSD = listSD[[metric]])
    data.4 <- XmR.Radar.Plot.prepare(data,L,U,metric = metric,
                                     type = "variability",group = "Variability decrease",
                                     XmR.type = "neg",
                                     selectMean = listMean[[metric]],selectSD = listSD[[metric]])
    dat <- rbind(dat, data.1, data.2, data.3, data.4)
  }
  return(dat)
}
#################################################################################################################
CUSUM.Radar.Plot.prepare <- function(data, L, U, metric, type, group, CUSUM.type, selectMean, selectSD) {
  h <- 5
  precursors <- levels(data$Precursor)
  precursors2 <- substring(precursors, first = 1, last = 3)
  QCno.length <- c()
  QCno.out.range <- c()
  for(j in seq_along(precursors)) {
    metricData <- getMetricData(data, precursors[j], L = L, U = U,
                                metric = metric, normalization = TRUE, selectMean, selectSD)
    QCno.length <- c(QCno.length,length(metricData))
    plot.data <- CUSUM.data.prepare(data, metricData, precursors[j], type, referenceValue = 0.5, decisionInterval = 5)

    if(CUSUM.type == "poz")
      QCno.out.range <- c(QCno.out.range,
                          length(plot.data[plot.data$CUSUM.poz >= h |
                                             plot.data$CUSUM.poz <= -h, ]$QCno))
    else
      QCno.out.range <- c(QCno.out.range,
                          length(plot.data[plot.data$CUSUM.neg >= h |
                                             plot.data$CUSUM.neg <= -h, ]$QCno))
  }
  dat <- data.frame(peptides = precursors2,
                    OutRangeQCno  = QCno.out.range,
                    group         = rep(group,length(precursors)),
                    #orderby       = seq(1:length(precursors)),
                    orderby       = seq(seq_along(precursors)),
                    metric        = rep(metric, length(precursors)),
                    tool          = rep("XmR",length(precursors)),
                    probability   = QCno.out.range/QCno.length
  )
  return(dat)
}
#################################################################################################
CUSUM.Radar.Plot.DataFrame <- function(data, data.metrics, L, U, listMean, listSD) {
  dat <- data.frame(peptides = c(), OutRangeQCno = c(), group = c(),
                    orderby = c(), metric = c(), tool = c(),
                    probability   = c()
  )
  for (metric in data.metrics) {
    data.1 <- CUSUM.Radar.Plot.prepare(data,L,U, metric = metric, type = "mean",
                                       group = "Mean increase",CUSUM.type = "poz",
                                       selectMean = listMean[[metric]],selectSD = listSD[[metric]])
    data.2 <- CUSUM.Radar.Plot.prepare(data,L,U, metric = metric, type = "mean",
                                       group = "Mean decrease", CUSUM.type = "neg",
                                       selectMean = listMean[[metric]],selectSD = listSD[[metric]])
    data.3 <- CUSUM.Radar.Plot.prepare(data,L,U, metric = metric, type = "variability",
                                       group = "Variability increase", CUSUM.type = "poz",
                                       selectMean = listMean[[metric]],selectSD = listSD[[metric]])
    data.4 <- CUSUM.Radar.Plot.prepare(data,L,U, metric = metric, type = "variability",
                                       group = "Variability decrease", CUSUM.type = "neg",
                                       selectMean = listMean[[metric]],selectSD = listSD[[metric]])
    dat <- rbind(dat, data.1, data.2, data.3, data.4)
  }
  return(dat)
}
#######################################################################################################
Decision.DataFrame.prepare <- function(data, metric, method, peptideThresholdRed,
                                       peptideThresholdYellow, L, U,type, selectMean, selectSD) {
  AcquiredTime <- data$AcquiredTime
  QCno <- seq_len(nrow(data))
  y <- rep(0,nrow(data))
  counter <- rep(0,nrow(data))

  precursors <- levels(data$Precursor)

  if(method == "XmR") {
    for(precursor in precursors) {
      metricData <- getMetricData(data, precursor, L = L, U = U,
                                  metric = metric, normalization = TRUE,selectMean,selectSD)
      #counter[1:length(metricData)] <- counter[1:length(metricData)]+1
      counter[seq_along(metricData)] <- counter[ seq_along(metricData)]+1
      plot.data <- XmR.data.prepare( metricData , L , U , type, selectMean, selectSD)
      sub <- plot.data[plot.data$InRangeOutRange == "OutRange",]
      y[sub$QCno] <- y[sub$QCno] + 1
    }
  } else if(method == "CUSUM") {
    for(precursor in precursors) {
      metricData <- getMetricData(data, precursor, L = L, U = U,
                                  metric = metric, normalization = TRUE,
                                  selectMean,selectSD)

      counter[seq_along(metricData)] <- counter[seq_along(metricData)]+1

      plot.data <- CUSUM.data.prepare(data, metricData, precursor, type, referenceValue = 0.5, decisionInterval = 5)
      decisionInterval <- 5
      sub <- plot.data[(plot.data$CUSUM.poz >= decisionInterval |
                          plot.data$CUSUM.poz <= -decisionInterval) |
                         (plot.data$CUSUM.neg >= decisionInterval |
                            plot.data$CUSUM.neg <= -decisionInterval), ]
      y[sub$QCno] <- y[sub$QCno] + 1
    }
  }
  max_QCno <- max(which(counter!=0))

  pr.y <- y[seq_len(max_QCno)]/counter[seq_len(max_QCno)]

  plot.data <- data.frame(AcquiredTime = AcquiredTime[seq_len(max_QCno)],
                          #QCno = rep(1:max_QCno,1),
                          QCno = rep(seq_len(max_QCno),1),
                          pr.y = pr.y,
                          group = ifelse(rep(type==1,max_QCno),
                                         rep("Metric mean",max_QCno),
                                         rep("Metric variability",max_QCno)
                          ),
                          metric = rep(metric,max_QCno),
                          bin = rep(0,max_QCno)
  )

  for (i in seq_len(max_QCno)) {
    if(plot.data$pr.y[i] > peptideThresholdRed){
      plot.data$bin[i] <- "Fail"
    }
    else if(plot.data$pr.y[i] > peptideThresholdYellow){
      plot.data$bin[i] <- "Warning"
    }
    else {
      plot.data$bin[i] <- "Pass"
    }
  }

  if(type == 2) {

    return(plot.data[-1,])
  }
  return(plot.data)
}
#######################################################################################################
number.Of.Out.Of.Range.Metrics <- function(data, data.metrics, method,
                                           peptideThresholdRed, peptideThresholdYellow,
                                           L, U, type, listMean, listSD) {

  metricCounterAboveRed <- 0
  metricCounterAboveYellowBelowRed <- 0
  precursors <- levels(data$Precursor)

  for (metric in data.metrics) {
    QCno <- seq_len(nrow(data))
    y <- rep(0,nrow(data))
    counter <- rep(0,nrow(data))
    for(precursor in precursors) {
      metricData <- getMetricData(data, precursor, L = L, U = U, metric = metric,
                                  normalization = TRUE,listMean[[metric]],listSD[[metric]])
      counter[seq_along(metricData)] <- counter[seq_along(metricData)]+1
      plot.data <- XmR.data.prepare(metricData , L , U ,type,
                                    selectMean = listMean[[metric]],selectSD = listSD[[metric]])

      sub <- plot.data[plot.data$InRangeOutRange == "OutRange",]
      y[sub$QCno] <- y[sub$QCno] + 1
    }
    max_QCno <- max(which(counter!=0))
    pr.y <- y[seq_len(max_QCno)]/counter[seq_len(max_QCno)]

    if(type == 2) {
      pr.y <- pr.y[-1]
    }

    aboveYellow <- which(pr.y > peptideThresholdYellow)
    aboveYellowBelowRed <- which(pr.y > peptideThresholdYellow & pr.y <= peptideThresholdRed)

    if(length(which(pr.y > peptideThresholdRed)) > 0) {
      metricCounterAboveRed = metricCounterAboveRed + 1
    }
    if(length(aboveYellowBelowRed) > 0) {
      metricCounterAboveYellowBelowRed <- metricCounterAboveYellowBelowRed + 1
    }
  }
  return(c(metricCounterAboveRed,metricCounterAboveYellowBelowRed))
}
####################################################################################################
SummaryPlot <- function(data = NULL, L = 1, U = 5, method = "CUSUM",
                        listMean=NULL, listSD=NULL) {
  if(is.null(data))
    return()
  if(!is.data.frame(data)){
    stop(data)
  }
  dat <- NULL
  data.metrics <- c(find_custom_metrics(data))
  remove <- c("MinStartTime","MaxEndTime")
  data.metrics <- data.metrics[!data.metrics %in% remove]
  if(method == "CUSUM"){
    dat <- CUSUM.River.DataFrame(data, data.metrics, L, U, listMean, listSD)
  }else if(method == "XmR") {
    dat <- XmR.River.DataFrame(data, data.metrics, L, U, listMean, listSD)
  }

  tho.hat.df <- get_CP_tho.hat(data, L, U, data.metrics, listMean, listSD)

  gg <- ggplot(dat)
  gg <- gg + geom_hline(yintercept=0, alpha=0.5)
  gg <- gg + geom_smooth(method="loess",aes(x=dat$QCno, y=dat$pr.y,colour = dat$group,
                                            group = dat$group))
  gg <- gg + geom_point(data = tho.hat.df, aes(x = tho.hat.df$tho.hat, y = tho.hat.df$y,
                                               colour = "Change point"))
  gg <- gg + scale_color_manual(breaks = c("Mean increase",
                                           "Mean decrease",
                                           "Variability increase",
                                           "Variability decrease",
                                           "Change point"),
                                values = c("Mean increase" = "#E69F00",
                                           "Mean decrease" = "#56B4E9",
                                           "Variability increase" = "#009E73",
                                           "Variability decrease" = "#D55E00",
                                           "Change point" = "red"),
                                guide='legend')
  gg <- gg + guides(colour = guide_legend(override.aes = list(linetype=c(1,1,1,1,0),
                                                              shape=c(NA,NA,NA,NA,16))))
  gg <- gg + facet_wrap(~metric,nrow = ceiling(length(data.metrics)/4))
  gg <- gg + annotate("text", x = 15, y = 1.3, label = "Mean")
  gg <- gg + annotate("text", x = 25, y = -1.3, label = "Variability")
  gg <- gg + scale_y_continuous(expand=c(0,0), limits = c(-1.4,1.4),
                                breaks = c(1,0.5,0,-0.5,-1) ,labels = c(1,0.5,0,"0.5","1"))
  gg <- gg + labs(x = "Time", y = "proportion of out of control \npeptides")
  gg <- gg + theme(plot.title = element_text(size=15, face="bold",
                                             margin = margin(10, 0, 10, 0)),
                   axis.text.x=element_text(size=12, vjust=0.5),
                   axis.text.y=element_text(size=12, hjust=0.5),
                   axis.title.y=element_text(size=12),
                   axis.title.x=element_text(size=12),
                   legend.text = element_text(size = 12),
                   legend.title=element_blank(),
                   plot.margin = unit(c(1,3,1,1), "lines")
  )
  theme_set(theme_gray(base_size = 15))
  gg
}
