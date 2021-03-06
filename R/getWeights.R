#' Optimize weights for model averaging.
#'
#' Function to constructed an optimal vector of weights for model averaging of
#' Linear Mixed Models based on the proposal of Zhang et al. (2014) of using Stein's Formular
#' to derive a suitable criterion based on the conditional Akaike Information Criterion as
#' proposed by Greven and Kneib. The underlying optimization used is a customized version
#' of the Augmented Lagrangian Method.
#'
#' @param models An list m containing all considered candidate models fitted by
#' \code{\link[lme4]{lmer}} of the lme4-package or of class
#' \code{\link[nlme]{lme}}.
#' @return An updated m containing a vector of weights for the underlying candidate models, value
#' of the m given said weights as well as the time needed.
#' @section WARNINGS : For models called via \code{gamm4} or \code{gamm}
#' no weight determination via this function is currently possible.
#' @author Benjamin Saefken & Rene-Marcel Kruse
#' @seealso \code{\link[lme4]{lme4-package}}, \code{\link[lme4]{lmer}},
#' \code{\link[lme4]{getME}}
#' @references Greven, S. and Kneib T. (2010) On the behaviour of marginal and
#' conditional AIC in linear mixed models. Biometrika 97(4), 773-789.
#' @references Zhang, X., Zou, G., & Liang, H. (2014). Model averaging and
#' weight choice in linear mixed-effects models. Biometrika, 101(1), 205-218.
#' @references Nocedal, J., & Wright, S. (2006). Numerical optimization.
#' Springer Science & Business Media.
#' @keywords weights, model averaging, augmented lagrangian method
#' @rdname getWeights
#' @export getWeights
#' @examples data(Orthodont, package = "nlme")
#' models <- list(
#'     model1 <- lmer(formula = distance ~ age + Sex + (1 | Subject) + age:Sex,
#'                data = Orthodont),
#'     model2 <- lmer(formula = distance ~ age + Sex + (1 | Subject),
#'                data = Orthodont),
#'     model3 <- lmer(formula = distance ~ age + (1 | Subject),
#'                  data = Orthodont),
#'     model4 <- lmer(formula = distance ~ Sex + (1 | Subject),
#'                 data = Orthodont))
#'
#' foo <- getWeights(models = models)
#' foo
#'
#'
getWeights <- function(models)
{
  m             <- models
  .envi         <- environment()
  # Creation of the variables required for the optimization of weights
  # TODO: neue Version vom folgenden Abschnitt:
  ##############################################################
  mAIC <- lapply(models, cAIC)
  # extract formulas
  frms <- sapply(m, function(x) Reduce(paste, deparse(formula(x))))
  # replace formulas, where the model was refitted
  refit <- sapply(mAIC, "[[", "new")
  if(any(refit))
    frms[which(refit)] <- sapply(mAIC[which(refit)], function(x) 
      Reduce(paste, deparse(formula(x$reducedModel))))
  
  # create modelcAICurning data.frame
  modelcAIC <- as.data.frame(do.call("rbind", lapply(mAIC, function(x)  
    round(unlist(x[c("loglikelihood", "df", "caic", "new")]), digits = 2))))
  modelcAIC[,4] <- as.logical(modelcAIC[,4])
  rownames(modelcAIC) <- make.unique(frms, sep = " % duplicate #")
  colnames(modelcAIC) <- c("cll",
                          "df",
                          "cAIC",
                          "Refit")
  ##############################################################
  # TODO: besser die größen auslesen:
  df            <- modelcAIC[[2]]
  tempm         <- m[[which.max(modelcAIC$df)]]
  seDF          <- getME(tempm, "sigma")
  varDF         <- seDF * seDF
  y             <- getME(m[[1]], "y")
  
  ## Mu über eine If Abfrage hinsichtlich der Objekt Klasse:
  mu            <- list()
  ## Mu über eine If Abfrage hinsichtlich der Objekt Klasse:
  # Für LMs, GLMs:
  if (any(class(m) %in% c("glm","lm")) & !("gam" %in% class(m))) {
    mu <- predict(m,type="response")
  }
  # Für LME und GAMMS
  if (any(names(m) == "mer")) {
    for(i in 1:length(m)){
      mu[[i]]     <- getME(m[[i]], "mu")
    }
    mu            <- t(matrix(unlist(mu), nrow = length(m), byrow = TRUE))  
  }  # TODO: that needs to be made more effective ...
  
  weights       <- rep(1/length(m), times = length(m))
  fun           <- find_weights <- function(w){(norm(y - matrix(mu %*% w), "F"))^(2) + 2 * varDF * (w %*% df)}
  eqfun         <- equal <-function(w){sum(w)}
  equB           <- 1
  lowb          <- rep(0, times = length(m))
  uppb          <- rep(1, times = length(m))
  nw            <- length(weights)
  funv 	        <- find_weights(weights)
  eqv 	        <- (sum(weights)-equB)
  rho           <- 0
  maxit         <- 400
  minit         <- 800
  delta         <- (1.0e-7)
  tol           <- (1.0e-8)
  # Start of optimization:
  j             <- jh <- funv
  lambda        <- c(0)
  constraint    <- eqv
  p             <- c(weights)
  hess          <- diag(nw)
  mue           <- nw
  .iters        <- 0
  targets            <- c(funv, eqv)
  tic           <- Sys.time()
  while( .iters < maxit ){
    .iters <- .iters + 1
    scaler <- c( targets[ 1 ], rep(1, 1) * max( abs(targets[ 2:(1  + 1) ]) ) )
    scaler <- c(scaler, rep( 1, length.out = length(p) ) )
    scaler <- apply( matrix(scaler, ncol = 1), 1,
                     FUN = function( x ) min( max( abs(x), tol ), 1/tol ) )
    res    <- .weightOptim(weights = p, lm = lambda, targets = targets,
                           hess = hess, lambda = mue, scaler = scaler, .envi = .envi)
    p      <- res$p
    lambda <- res$y
    hess   <- res$hess
    mue    <- res$lambda
    temp   <- p
    funv 	 <- find_weights(temp)
    eqv 	 <- (sum(temp)-equB)
    targets     <- c(funv, eqv)
      # Change of the target function through optimization
    tt     <- (j - targets[ 1 ]) / max(targets[ 1 ], 1)
    j      <- targets[ 1 ]
    constraint <- targets[ 2 ]
    if( abs(constraint) < 10 * tol ) {
      rho  <- 0
      mue  <- min(mue, tol)
    }
    if( c( tol + tt ) <= 0 ) {
      lambda <- 0
      hess  <- diag( diag ( hess ) )
    }
    if( sqrt(sum( (c(tt, eqv))^2 )) <= tol ) {
      maxit <- .iters
    }
  }
  toc <- Sys.time() - tic
  ans <- list("weights" = p, "functionvalue" = j,
              "duration" = toc)
  return( ans )
}
