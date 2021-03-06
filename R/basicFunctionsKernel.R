

#' FlexCoDE Fit Conditional Density Estimation via Regression
#'
#' @param xTrain Covariates x used to train the model (one observation per row)
#' @param zTrain Responses z used to train the model  (matrix with one column; one observation per row)
#' @param xValidation Covariates x used to tune the model (one observation per row; same number of columns as xTrain)
#' @param zValidation Responses z used to tune the model  (matrix with one column; one observation per row)
#' @param xTest Covariates x used to estimate risk of final model (one observation per row; same number of columns as xTrain). Default is NULL
#' @param zTest Responses z used to estimate risk of final model  (matrix with one column; one observation per row). Default is NULL
#' @param nIMax Maximum possible number of components of the series expansion (that is, the function will find the best I<nIMax). Default is 100
#' @param regressionFunction a function indicating which regression method will be used to estimate the expansion coefficients. Currently can be one of
#' @param regressionFunction.extra extra parameters to be sent to regression function; see the regression you want to use to check what are the available parameters
#' @param system Basis for z. Current options are "Fourier", "Cosine" and "discrete". Default is "Fourier"
#' @param chooseDelta Should delta, the cutoff to remove spurious bumps, be chosen?
#' @param deltaGrid Grid of threshold deltas (betwen 0 and 0.5). Default value is seq(0,0.4,0.05).
#' @param verbose Should we print what we are doing? Default is TRUE.
#'
#' @return Returns the fitted estimated conditional density, and object of the class FlexCoDE. The return value is an object with the following components:
#' \item{zMin, zMax}{Minimum and maximum value of z}
#' \item{nIMax}{Maximum number of expansion coefficients (user input). Default is minimum between 25 and number of training samples.}
#' \item{system}{Basis used for expanding the response}
#' \item{zTrain}{zTrain (user input)}
#' \item{xTrain}{xTrain (user input)}
#' \item{regressionObject}{Object with fitted regressions. Class and content depend on which regression method was chosen by user}
#' \item{errors}{Estimated errors for each value of I (number of expansion coefficients) using validation set}
#' \item{bestI}{Optimal number of I according to validation set}
#' \item{bestError}{Estimated error of model with bestI expansion terms according to validation set}
#' \item{bestDelta}{Optimal value of threshold delta according to validation set}
#' \item{estimatedRisk}{(If user provides xTest and zTest) Estimated risk (error) according to test set)}
#'
#' @example ../testPackageKernel.R
#'
#' @export
fitFlexCoDEKernel=function(kernelTrainTrain,zTrain,kernelValidationTrain,zValidation,kernelTestTrain=NULL,zTest=NULL,nIMax=min(25,length(zTrain)),regressionFunction,regressionFunction.extra=NULL,system="Fourier",deltaGrid=seq(0,0.4,0.05),chooseDelta=TRUE,verbose=TRUE)
{

  objectCDE=NULL
  objectCDE$zMax=max(zTrain)
  objectCDE$zMin=min(zTrain)
  zTrain=(zTrain-objectCDE$zMin)/(objectCDE$zMax-objectCDE$zMin)

  class(objectCDE)="FlexCoDEKernel"
  objectCDE$verbose=verbose

  if(verbose) print("Transforming Response")
  responseFourier=calculateBasis(zTrain,nIMax,system)
  if(verbose) print("Fitting Regression Functions")
  regressionObject=regressionFunction(kernelX=kernelTrainTrain,
                                      responses=responseFourier,
                                      extra=regressionFunction.extra)
  objectCDE$nIMax=nIMax
  objectCDE$system=system
  objectCDE$zTrain=zTrain
  objectCDE$regressionObject=regressionObject
  rm(regressionObject,kernelTrainTrain,zTrain,responseFourier)
  gc(verbose = FALSE)

  zValidation=(zValidation-objectCDE$zMin)/(objectCDE$zMax-objectCDE$zMin)

  basisZValidation=calculateBasis(zValidation,
                                  objectCDE$nIMax,objectCDE$system) # returns matrix length(z)xnIMax with the basis for z

  if(verbose) print("Tuning Number of Expansion Coefficients (I)")
  coefficientsXValidation=predict(objectCDE$regressionObject,
                                  kernelValidationTrain)
  term1=1/2*colMeans(coefficientsXValidation^2)
  term1=cumsum(term1)

  term2=colMeans(coefficientsXValidation*basisZValidation[,1:ncol(coefficientsXValidation),drop=F])
  term2=cumsum(term2)
  objectCDE$errors=term1-term2
  objectCDE$bestI=which.min(objectCDE$errors)
  objectCDE$bestError=min(objectCDE$errors)

  if(chooseDelta)
  {
    if(verbose) print("Choosing optimal cutoff Delta")
    delta=chooseDeltaKernel(objectCDE, kernelValidationTrain,objectCDE$zMin+(objectCDE$zMax-objectCDE$zMin)*zValidation,deltaGrid)
    objectCDE$bestDelta=delta
  } else {
    objectCDE$bestDelta=0
  }

  if(!is.null(kernelTestTrain)&!is.null(zTest))
  {
    if(verbose) print("Estimating risk on test set")
    error=estimateErrorFlexCoDEKernel(objectCDE,kernelTestTrain,zTest,se=TRUE)
    objectCDE$estimatedRisk=error
  }

  if(objectCDE$bestI==objectCDE$nIMax)
    warning("\n the optimal I found was exactly nIMax; try increasing nIMax if you want to improve performance")

  return(objectCDE)
}

#' Choose threshold value to remove spurius bumps
#'
#' This function is typically not directly used by the user; it is used inside  \code{\link{fitFlexCoDE}}
#'
#' @param objectCDE An object of the class FlexCoDE with a fitted CDE, typically fitted used \code{\link{fitFlexCoDE}} beforehand
#' @param xValidation Covariates x used to validate (tune) the model (one x observation per row).
#' @param zValidation Responses z used to validate (tune) the model  (matrix with 1 column). Each row corresponds to a row of the xValidation argument
#'
#' @return Best delta
chooseDeltaKernel = function(objectCDE, kernelValidationTrain,
                             zValidation,deltaGrid=seq(0,0.4,0.05))
{
  if(class(objectCDE)!='FlexCoDEKernel')
    stop("objectCDE should be of class FlexCoDEKernel")
  error=rep(NA,length(deltaGrid))
  if(objectCDE$verbose) cat("\n Progress Bar:\n")
  for(ii in 1:length(deltaGrid))
  {
    if(objectCDE$verbose) cat(paste(c(rep("|",ii),rep(" ",length(deltaGrid)-ii),"|\n"),collapse=""))
    objectCDE$bestDelta=deltaGrid[ii]
    estimateErrors=estimateErrorFlexCoDEKernel(objectCDE=objectCDE,
                                               kernelTestTrain=kernelValidationTrain,zTest=zValidation,se=FALSE)
    error[ii]=estimateErrors
  }
  #plot(error)
  whichMin=(1:length(error))[error==min(error)]
  bestDelta=deltaGrid[max(whichMin)]
  return(bestDelta)
}


#' Estimate error (risk) of FlexCoDE object via test set
#'
#' @param objectCDE is an object of the class FlexCoDEtypically typically fitted used \code{\link{fitFlexCoDE}} beforehand
#' @param xTest Covariates x of the sample used to test the model (one observation per row)
#' @param zTest Response z of the sample used to test the model (one observation per row)
#' @param se Should standard error be computed? Default is TRUE
#'
#' @return Estimated error (with SE if desired)
#' @export
#'
estimateErrorFlexCoDEKernel=function(objectCDE,kernelTestTrain,zTest,se=TRUE)
{
  if(class(objectCDE)!="FlexCoDEKernel")
    stop("objectCDE should be of class FlexCoDEKernel")



  zGrid=seq(objectCDE$zMin[1],objectCDE$zMax[1],length.out=500)

  predictedComplete=predict(objectCDE,kernelNewTrain = kernelTestTrain,B=length(zGrid))
  predictedComplete=predictedComplete$CDE*(objectCDE$zMax-objectCDE$zMin)

  colmeansComplete=colMeans(predictedComplete^2)
  sSquare=mean(colmeansComplete)

  n=length(zTest)
  predictedObserved=apply(as.matrix(1:n),1,function(xx) { index=which.min(abs(zTest[xx]-zGrid))
  return(predictedComplete[xx,index])
  })
  likeli=mean(predictedObserved)

  if(!se)
    return(1/2*sSquare-likeli)

  # Bootstrap
  output=NULL
  output$mean=1/2*sSquare-likeli

  boot=1000
  meanBoot=apply(as.matrix(1:boot),1,function(xx){
    sampleBoot=sample(1:n,replace=T)

    predictedCompleteBoot=predictedComplete[sampleBoot,]
    zTestBoot=zTest[sampleBoot]

    colmeansComplete=colMeans(predictedCompleteBoot^2)
    sSquare=mean(colmeansComplete)

    predictedObserved=apply(as.matrix(1:n),1,function(xx) { index=which.min(abs(zTestBoot[xx]-zGrid))
    return(predictedCompleteBoot[xx,index])
    })
    likeli=mean(predictedObserved)
    return(1/2*sSquare-likeli)
  })
  output$seBoot=sqrt(var(meanBoot))
  return(output)


}


#' Evaluates the estimated  density of new observations (testing points) of a "FlexCoDE" object
#'
#' @param objectCDE Object of the class "FlexCoDE", typically fitted used \code{\link{fitFlexCoDE}} beforehand
#' @param xNew Matrix with nTest rows and same number of columns as xTrain, containing x's for which the estimates are desired.
#' @param B Number of point where f(z|x) will be evaluated (on the z scale). This will be equally spaced between zMin and zMax
#'
#' @return The return value is an object with the following components
#' \item{z}{Points where the density was evaluate}
#' \item{CDE }{Matrix with value of the density at points z. Each row corresponds to a different observation x (i-th row of CDE corresponds to i-th row of xTest).}
#' \item{th}{(If predictionBandProb is not FALSE) Threshold values for each estimated density. The region where estimated densities are above these values have the approximate coverage probability desired. See  \code{\link{plot.FlexCoDE}} for ploting these regions.}
#'
#' @examples # See \code{\link{fitFlexCoDE}}
#'
#' @export
#'
predict.FlexCoDEKernel=function(objectCDE,kernelNewTrain,B=1000,predictionBandProb=FALSE)
{

  if(class(objectCDE)!="FlexCoDEKernel")
    stop("Object should be of type FlexCoDEKernel")
  zGrid=seq(from=0,to=1,length.out=B)

  if(is.null(objectCDE$bestI))
    objectCDE$bestI=objectCDE$nIMax

  coeff=predict(objectCDE$regressionObject,kernelNewTrain,maxTerms=objectCDE$bestI)

  basisZNew=calculateBasis(zGrid,objectCDE$bestI,objectCDE$system) # returns matrix length(z)xnIMax with the basis for z

  estimates=coeff%*%t(basisZNew)

  binSize=(1)/(B+1)

  delta=ifelse(!is.null(objectCDE$bestDelta),objectCDE$bestDelta,0)


  estimates=t(apply(estimates,1,function(xx).normalizeDensity(binSize,xx,delta)))

  estimates=estimates/(objectCDE$zMax-objectCDE$zMin)
  returnValue=NULL
  returnValue$CDE=estimates
  returnValue$z=seq(from=objectCDE$zMin,to=objectCDE$zMax,length.out=B)

  if(predictionBandProb==FALSE)
    return(returnValue)


  th=matrix(NA,nrow(returnValue$CDE),1)
  for(i in 1:nrow(returnValue$CDE))
  {

    th[i]=.findThresholdHPD((objectCDE$zMax-objectCDE$zMin)/B,returnValue$CDE[i,],predictionBandProb)


  }

  returnValue$th=th
  return(returnValue)

  th=matrix(NA,nrow(returnValue$CDE),2)
  for(i in 1:nrow(returnValue$CDE))
  {
    interval=.findThresholdSymmetricMode((objectCDE$zMax-objectCDE$zMin)/B,
                                         returnValue$CDE[i,],
                                         predictionBandProb)
    intervalExtended=interval[1]:interval[2]
    for(k in 1:length(intervalExtended))
    {
      if(returnValue$CDE[i,intervalExtended][k]==0)
      {
        interval[1]=interval[1]+1
      } else {
        break;
      }
    }
    for(k in length(intervalExtended):1)
    {
      if(returnValue$CDE[i,intervalExtended][k]==0)
      {
        interval[2]=interval[2]-1
      } else {
        break;
      }
    }
    th[i,1]=returnValue$z[interval[1]]
    th[i,2]=returnValue$z[interval[2]]
  }
  returnValue$th=th
  return(returnValue)

}

#' Print object of classe FlexCoDE
#'
#' @param objectCDE Object of the class "FlexCoDE", typically fitted used \code{\link{fitFlexCoDE}} beforehand
#'
#' @return returns information regarding the fitted model
#'
#' @export
#'
print.FlexCoDEKernel=function(objectCDE)
{
  if(class(objectCDE)!="FlexCoDEKernel")
    stop("Object should be of class FlexCoDEKernel")
  cat("FlexCoDE - Kernel Flexible Conditional Density Estimator \n \n \n")
  cat("####### Caracteristic of the fitted CDE:\n\n")
  cat(paste("Regression Method Used:",class(objectCDE$regressionObject)),"\n")

  cat(paste("Best Number of Expansion Coefficients Sected:",(objectCDE$bestI)),"\n")

  cat(paste("Basis used:",objectCDE$system,"\n"))

  if(!is.null(objectCDE$estimatedRisk)) cat(paste("Estimated risk on test set: ",objectCDE$estimatedRisk$mean," (se: ",objectCDE$estimatedRisk$seBoot,")","\n",sep=""))

  cat("\n")
  cat("####### Caracteristic of the fitted regression:\n\n")
  print(objectCDE$regressionObject,bestI=objectCDE$bestI,nameCovariates=objectCDE$covariateNames)

}


#' Plots examples of estimated densities together with real response
#'
#' @param objectCDE Object of the class "FlexCoDE", typically fitted used \code{\link{fitFlexCoDE}} beforehand
#' @param xTest Covariates x of the sample used to test the model (one observation per row)
#' @param zTest Response z of the sample used to test the model (one observation per row)
#' @param nPlots Number of desired densities to be ploted (which will be picked at random). Default is minimum between 8 and number of testing points
#' @param fontSize Font size of axis labels and legend
#' @param lineWidth Line width of the curves to be ploted
#' @param predictionBandProb Either a number indicating the probability for the highest predictive density region desired  or FALSE if bands are not desired. Default is FALSE
#' @param lineWidthPred Line width of the prediction bands to be ploted
#' @return Plot with estimated densities
#'
#' @examples # See \code{\link{fitFlexCoDE}}
#'
#' @export
#'
plot.FlexCoDEKernel=function(objectCDE,kernelTestTrain,zTest,nPlots=min(nrow(kernelTestTrain),9),fontSize=12,lineWidth=1,predictionBandProb=FALSE,lineWidthPred=0.6)
{

  if(is.null(kernelTestTrain))
    stop("Please provide kernelTestTrain")


  if(is.null(zTest))
    stop("Please provide zTest")

  if(class(objectCDE)!="FlexCoDEKernel")
    stop("objectCDE needs to be of class FlexCoDEKernel")
  if(objectCDE$verbose)  print("Calculating predicted values")
  predictedValues=predict(objectCDE,kernelTestTrain,B=500,predictionBandProb=predictionBandProb)


  randomOrder=sample(1:nrow(kernelTestTrain),nPlots,replace=FALSE)
  if(objectCDE$verbose) print("Creating plots")


  data=data.frame(x=predictedValues$z,y=predictedValues$CDE[randomOrder[1],],dataPoint=rep(1,length(predictedValues$z)),vertical=zTest[randomOrder[1]])
  if(nPlots>1)
  {
    for(i in 2:nPlots)
    {
      dataB=data.frame(x=predictedValues$z,y=predictedValues$CDE[randomOrder[i],],dataPoint=rep(i,length(predictedValues$z)),vertical=zTest[randomOrder[i]])
      data=rbind(data,dataB)
    }
  }

  g=ggplot2::ggplot(data,ggplot2::aes(x=x,y=y))+ggplot2::geom_line(size=lineWidth,color=2)+ggplot2::xlab("Response")+
    ggplot2::ylab("Estimated Density")+
    ggplot2::geom_vline(ggplot2::aes(xintercept=vertical),size=lineWidth)+
    ggplot2::theme(axis.title=ggplot2::element_text(size=fontSize,face="bold"))+ ggplot2::facet_wrap(~ dataPoint)
  print(g)


  if(predictionBandProb==FALSE)
    return()

  eps=0.35
  k=nrow(kernelTestTrain)
  plot(x=1:k,y=zTest,main="",ylab="Prediction Region",cex.main=1.4,cex.axis=1.4,cex.lab=1.4,cex=1.5,col=1,xaxt="n",xlim=c(0.5,k+0.5),pch=16,ylim=c(objectCDE$zMin,objectCDE$zMax),xlab="Sample",bty="l")
  for(ii in 1:k)
  {
    whichLarger=predictedValues$CDE[ii,]>predictedValues$th[ii]
    runs=rle(whichLarger>0)
    nRuns=length(runs$values)

    cumulative=cumsum(runs$lengths)
    for(jj in 1:nRuns)
    {
      if(runs$values[jj]==TRUE)
      {
        if(jj==1)
        {
          lower=objectCDE$zMin
          upper=predictedValues$z[cumulative[jj]]
          lines(c(ii,ii),c(lower,upper),col=1,lwd=lineWidthPred)
          lines(c(ii-eps,ii+eps),c(lower,lower),col=1,lwd=lineWidthPred)
          lines(c(ii-eps,ii+eps),c(upper,upper),col=1,lwd=lineWidthPred)
          next;
        }
        #points(rep(ii,sum(whichLarger)),predicted$z[whichLarger],pch=18,cex=0.9,col=2)
        lower=predictedValues$z[cumulative[jj-1]]
        upper=predictedValues$z[cumulative[jj]]
        lines(c(ii,ii),c(lower,upper),col=1,lwd=lineWidthPred)

        lines(c(ii-eps,ii+eps),c(lower,lower),col=1,lwd=lineWidthPred)
        lines(c(ii-eps,ii+eps),c(upper,upper),col=1,lwd=lineWidthPred)
      }
    }
  }

  points(x=1:k,y=zTest,main="",ylab="Estimate",cex.main=1.4,cex.axis=1.4,cex.lab=1.4,cex=1.5,col=1,xaxt="n",xlim=c(0.5,k+0.5),pch=16,ylim=c(min(zTrain),max(zTrain)),xlab="Sample")


}




#' Plots examples of estimated densities together with real response
#'
#' @param objectCDE_binded Object of the class "FlexCoDE_binded", typically obtained using \code{\link{bindFlexCoDE}} beforehand
#' @param xTest Covariates x of the sample used to test the model (one observation per row)
#' @param zTest Response z of the sample used to test the model (one observation per row)
#' @param nPlots Number of desired densities to be ploted (which will be picked at random). Default is minimum between 8 and number of testing points
#' @param fontSize Font size of axis labels and legend
#' @param lineWidth Line width of the curves to be ploted

#' @return Plot with estimated densities
#'
#' @examples # See \code{\link{bindFlexCoDEKernel}}
#'
#' @export
plot.FlexCoDE_bindedKernel=function(objectCDE_binded,kernelTestTrain,zTest,nPlots=min(nrow(kernelTestTrain),8),fontSize=12,lineWidth=1)
{


  if(is.null(kernelTestTrain))
    stop("Please provide kernelTestTrain")


  if(is.null(zTest))
    stop("Please provide zTest")

  if(class(objectCDE_binded)!="FlexCoDE_bindedKernel")
    stop("objectCDE_binded needs to be of class FlexCoDE_bindedKernel")
  if(objectCDE_binded[[1]]$verbose)  print("Calculating predicted values")

  predictedValues=list()
  for(b in 1:length(objectCDE_binded))
  {
    predictedValues[[b]]=predict(objectCDE_binded[[b]],kernelTestTrain,B=500)
  }


  namesEstimators=sapply(objectCDE_binded, function(x)
    class(x$regressionObject))
  randomOrder=sample(1:nrow(kernelTestTrain),nPlots,replace=FALSE)

  if(objectCDE_binded[[1]]$verbose)  print("Creating plots")

  x=c(sapply(predictedValues, function(x)x$z))
  y=c(sapply(predictedValues, function(x)x$CDE[randomOrder[1],]))
  data=data.frame(x=x,y=y,Estimator=as.factor(rep(namesEstimators,each=length(predictedValues[[1]]$z))),dataPoint=1,vertical=zTest[randomOrder[1]])
  if(nPlots>1)
  {
    for(i in 2:nPlots)
    {
      y=c(sapply(predictedValues, function(x)x$CDE[randomOrder[i],]))
      dataB=data.frame(x=x,y=y,Estimator=as.factor(rep(namesEstimators,each=length(predictedValues[[1]]$z))),dataPoint=i,vertical=zTest[randomOrder[i]])
      data=rbind(data,dataB)
    }
  }

  ggplot2::ggplot(data,ggplot2::aes(x=x,y=y,color=Estimator))+ggplot2::geom_line(size=lineWidth)+ggplot2::xlab("Response")+
    ggplot2::ylab("Estimated Density")+
    ggplot2::geom_vline(ggplot2::aes(xintercept=vertical),size=lineWidth)+
    ggplot2::theme(axis.title=ggplot2::element_text(size=fontSize,face="bold"))+ ggplot2::facet_wrap(~ dataPoint)+
    ggplot2::theme(legend.direction = "horizontal",legend.position = "top",legend.title=ggplot2::element_text(size=16,face="bold"),legend.text=ggplot2::element_text(size=fontSize),axis.title=ggplot2::element_text(size=fontSize,face="bold"))

}


#' Binds together objects of the class "FlexCoDE"
#'
#' @param objectCDE1 An object of the class FlexCoDE with a fitted CDE, typically fitted used \code{\link{fitFlexCoDE}} beforehand
#' @param objectCDE2 An object of the class FlexCoDE with a fitted CDE, typically fitted used \code{\link{fitFlexCoDE}} beforehand
#' @param ... other objects of the class FlexCoDE with a fitted CDE, typically fitted used \code{\link{fitFlexCoDE}} beforehand
#'
#'
#' @return list with all objects combined. Result is of the class "FlexCoDE_binded"
#' @example ../testPackageBind.R
#'
#' @export
#'
bindFlexCoDEKernel=function(objectCDE1,objectCDE2,...)
{
  if(class(objectCDE1)!="FlexCoDEKernel")
    stop("All objects should be of type FlexCoDEKernel")
  returnValue=append(list(objectCDE1,objectCDE2),list(...))
  class(returnValue)="FlexCoDE_bindedKernel"
  return(returnValue)
}



#' Finds best linear combination of several FlexCoDE estimates
#'
#' @param objectCDE_binded An object of the class FlexCoDE_binded with a fitted CDE, typically fitted used \code{\link{bindFlexCoDE}} beforehand
#' @param xValidation Covariates x used to validate (tune) the model (one x observation per row).
#' @param zValidation Responses z used to validate (tune) the model  (matrix with 1 column). Each row corresponds to a row of the xValidation argument
#' @param xTest Covariates x used to estimate risk of final model (one observation per row; same number of columns as xTrain). Default is NULL
#' @param zTest Responses z used to estimate risk of final model  (matrix with one column; one observation per row). Default is NULL
#' @return Returns an object of the class "combinedFlexCoDE" which contains the weights best linear combination of the input models, together with all fitted models
#'
#' @example ../testPackageCombined.R
#'
#' @export
combineFlexCoDEKernel=function(objectCDE_binded,kernelValidationTrain,zValidation,kernelTestTrain=NULL,zTest=NULL)
{

  if(class(objectCDE_binded)!="FlexCoDE_bindedKernel")
    stop("Class of objectCDE_binded should be FlexCoDE_bindedKernel")
  predictedValues=list()
  for(b in 1:length(objectCDE_binded))
  {
    predictedValues[[b]]=predict(objectCDE_binded[[b]],kernelValidationTrain,B=500)
  }

  grid=predictedValues[[1]]$z
  estimatesValidation=lapply(predictedValues, function(x)x$CDE)


  width=grid[2]-grid[1]
  nModels=length(estimatesValidation)

  B=matrix(0,nModels,nModels)
  for(i in 1:nModels)
  {
    for(j in 1:nModels)
    {
      B[i,j]=mean(width*rowSums(estimatesValidation[[i]]*estimatesValidation[[j]]))
    }
  }

  whichZ=apply(as.matrix(zValidation),1,function(x){
    which.min(abs(x-grid))
  })
  b=rep(NA,nModels)
  for(i in 1:nModels)
  {
    m=estimatesValidation[[i]]
    b[i]=mean(m[(1:nrow(m)) + nrow(m) * (whichZ - 1)])
  }

  weights=quadprog::solve.QP(Dmat=B, dvec=b, Amat=t(rbind(1,diag(nModels))), bvec=c(1,rep(0,nModels)), meq=1, factorized=FALSE)
  weights$solution[weights$solution<0]=0
  weights$solution=weights$solution/sum(weights$solution)



  returnValue=list(objectCDEs=objectCDE_binded,weights=weights$solution)
  class(returnValue)="combinedFlexCoDEKernel"

  rm(objectCDE_binded)
  gc(verbose = FALSE)

  if(!is.null(kernelTestTrain)&!is.null(zTest))
  {
    if(returnValue$objectCDEs[[1]]$verbose) print("Estimating risk on test set")
    error=estimateErrorCombined(returnValue,kernelTestTrain,zTest,se=TRUE)
    returnValue$estimatedRisk=error
  }


  return(returnValue)
}

#' Evaluates the estimated  density of new observations (testing points) of a "combinedFlexCoDE" object
#'
#' @param objectCDE Object of the class "combinedFlexCoDE", typically fitted used \code{\link{combineFlexCoDE}} beforehand
#' @param xNew Matrix with nTest rows and same number of columns as xTrain, containing x's for which the estimates are desired.
#' @param B Number of point where f(z|x) will be evaluated (on the z scale). This will be equally spaced between zMin and zMax
#'
#' @return The return value is an object with the following components
#' \item{z}{Points where the density was evaluate}
#' \item{CDE }{Matrix with value of the density at points z. Each row corresponds to a different observation x (i-th row of CDE corresponds to i-th row of xTest).}
#' @export
#'
#' @examples # See \code{\link{combineFlexCoDE}}
predict.combinedFlexCoDEKernel=function(objectCombined,kernelNewTrain,B=1000)
{
  if(class(objectCombined)!="combinedFlexCoDEKernel")
    stop("objectCombined should be of class combinedFlexCoDEKernel")

  predictedValues=list()
  for(b in 1:length(objectCombined$objectCDEs))
  {
    predictedValues[[b]]=predict(objectCombined$objectCDEs[[b]],kernelNewTrain,B=500)
  }

  grid=predictedValues[[1]]$z
  estimatesValidation=lapply(predictedValues, function(x)x$CDE)

  predictedValuesFinal=matrix(0,nrow(estimatesValidation[[1]]),ncol(estimatesValidation[[1]]))
  for(b in 1:length(estimatesValidation))
  {
    predictedValuesFinal=predictedValuesFinal+estimatesValidation[[b]]*objectCombined$weights[b]
  }

  returnValue=NULL
  returnValue$CDE=predictedValuesFinal
  returnValue$z=grid


  return(returnValue)

}

#' Print object of classe combinedFlexCoDE
#'
#' @param objectCDE Object of the class "combinedFlexCoDE", typically fitted used \code{\link{combineFlexCoDE}} beforehand
#'
#' @return returns information regarding the fitted model
#' @export
#'
print.combinedFlexCoDEKernel=function(objectCombined)
{
  if(class(objectCombined)!="combinedFlexCoDEKernel")
    stop("objectCombined should be of class combinedFlexCoDEKernel")

  cat("Object of class combinedFlexCoDEKernel containing",length(objectCombined$weights),"fitted FlexCoDE regression estimators with weights \n ",objectCombined$weights,"\n respectively \n")
  cat("\n Estimators use the following regression methods respectively: \n")
  for(i in 1:length(objectCombined$weights))
  {
    cat(class(objectCombined$objectCDEs[[i]]$regressionObject),"\n")
  }

  if(!is.null(objectCombined$estimatedRisk))
  {
    cat(paste("Estimated risk on test set: ",objectCombined$estimatedRisk$mean," (se: ",objectCombined$estimatedRisk$seBoot,")","\n",sep=""))
  }

  cat("\n \n ############################## \n")
  cat("############################## \n \n")
  cat("\n Regression fits are the following: \n ")
  for(i in 1:length(objectCombined$weights))
  {
    cat("\n ############################## \n")
    cat("\n Fit ",i,":\n",sep = "")
    print(objectCombined$objectCDEs[[i]])
  }
}


#' Plots examples of estimated densities together with real response
#'
#' @param objectCombined Object of the class "combinedFlexCoDE", typically fitted used \code{\link{combineFlexCoDE}} beforehand
#' @param xTest Covariates x of the sample used to test the model (one observation per row)
#' @param zTest Response z of the sample used to test the model (one observation per row)
#' @param nPlots Number of desired densities to be ploted (which will be picked at random). Default is minimum between 8 and number of testing points
#' @param fontSize Font size of axis labels and legend
#' @param lineWidth Line width of the curves to be ploted
#'
#'
#' @return Plot with estimated densities
#' @export
#'
#' @examples # See \code{\link{combineFlexCoDE}}
plot.combinedFlexCoDEKernel=function(objectCombined,kernelTestTrain,zTest,nPlots=min(nrow(kernelTestTrain),8),fontSize=12,lineWidth=1)
{


  if(is.null(kernelTestTrain))
    stop("Please provide kernelTestTrain")


  if(is.null(zTest))
    stop("Please provide zTest")

  if(class(objectCombined)!="combinedFlexCoDEKernel")
    stop("objectCombined needs to be of class combinedFlexCoDEKernel")

  if(objectCombined$objectCDEs[[1]]$verbose)  print("Calculating predicted values")
  predictedValues=predict(objectCombined,kernelTestTrain,B=500)

  randomOrder=sample(1:nrow(xTest),nPlots,replace=FALSE)
  if(objectCombined$objectCDEs[[1]]$verbose) print("Creating plots")

  data=data.frame(x=predictedValues$z,y=predictedValues$CDE[randomOrder[1],],dataPoint=rep(1,length(predictedValues$z)),vertical=zTest[randomOrder[1]])
  if(nPlots>1)
  {
    for(i in 2:nPlots)
    {
      dataB=data.frame(x=predictedValues$z,y=predictedValues$CDE[randomOrder[i],],dataPoint=rep(i,length(predictedValues$z)),vertical=zTest[randomOrder[i]])
      data=rbind(data,dataB)
    }
  }

  ggplot2::ggplot(data,ggplot2::aes(x=x,y=y))+ggplot2::geom_line(size=lineWidth,color=2)+ggplot2::xlab("Response")+
    ggplot2::ylab("Estimated Density")+
    ggplot2::geom_vline(ggplot2::aes(xintercept=vertical),size=lineWidth,color=2)+
    ggplot2::theme(axis.title=ggplot2::element_text(size=fontSize,face="bold"))+ ggplot2::facet_wrap(~ dataPoint)


}


#' Estimate error (risk) of combinedFlexCoDE object via test set
#'
#' @param objectCombined Object of the class "combinedFlexCoDE", typically fitted used \code{\link{combineFlexCoDE}} beforehand
#' @param xTest Covariates x of the sample used to test the model (one observation per row)
#' @param zTest Response z of the sample used to test the model (one observation per row)
#' @param se Should standard error be computed? Default is TRUE
#'
#' @return Estimated error (with SE if desired)
#' @export
#'
estimateErrorCombinedKernel=function(objectCombined,kernelTestTrain,zTest,se=TRUE)
{

  if(class(objectCombined)!="combinedFlexCoDEKernel")
    stop("objectCombined should be of class combinedFlexCoDEKernel")

  zGrid=seq(objectCombined$objectCDEs[[1]]$zMin[1],objectCombined$objectCDEs[[1]]$zMax,length.out=500)

  predictedComplete=predict(objectCombined,xNew = kernelTestTrain,B=length(zGrid))
  predictedComplete=predictedComplete$CDE*(objectCombined$objectCDEs[[1]]$zMax-objectCombined$objectCDEs[[1]]$zMin)

  colmeansComplete=colMeans(predictedComplete^2)
  sSquare=mean(colmeansComplete)

  n=length(zTest)
  predictedObserved=apply(as.matrix(1:n),1,function(xx) { index=which.min(abs(zTest[xx]-zGrid))
  return(predictedComplete[xx,index])
  })
  likeli=mean(predictedObserved)

  if(!se)
    return(1/2*sSquare-likeli)

  # Bootstrap
  output=NULL
  output$mean=1/2*sSquare-likeli

  boot=1000
  meanBoot=apply(as.matrix(1:boot),1,function(xx){
    sampleBoot=sample(1:n,replace=T)

    predictedCompleteBoot=predictedComplete[sampleBoot,]
    zTestBoot=zTest[sampleBoot]

    colmeansComplete=colMeans(predictedCompleteBoot^2)
    sSquare=mean(colmeansComplete)

    predictedObserved=apply(as.matrix(1:n),1,function(xx) { index=which.min(abs(zTestBoot[xx]-zGrid))
    return(predictedCompleteBoot[xx,index])
    })
    likeli=mean(predictedObserved)
    return(1/2*sSquare-likeli)
  })
  output$seBoot=sqrt(var(meanBoot))
  return(output)


}

