% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/basicFunctions.R
\name{estimateErrorCombined}
\alias{estimateErrorCombined}
\title{Estimate error (risk) of combinedFlexCoDE object via test set}
\usage{
estimateErrorCombined(objectCombined, xTest, zTest, se = TRUE)
}
\arguments{
\item{objectCombined}{Object of the class "combinedFlexCoDE", typically fitted used \code{\link{combineFlexCoDE}} beforehand}

\item{xTest}{Covariates x of the sample used to test the model (one observation per row)}

\item{zTest}{Response z of the sample used to test the model (one observation per row)}

\item{se}{Should standard error be computed? Default is TRUE}
}
\value{
Estimated error (with SE if desired)
}
\description{
Estimate error (risk) of combinedFlexCoDE object via test set
}

