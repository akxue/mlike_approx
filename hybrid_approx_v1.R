

library(dplyr)
library(rpart)
library(VGAM)    # for log1mexp() function

## available functions in this file
## 
## (1) log_det()
## (2) preprocess()
## (3) approx_lil()
##
## -----------------------------------------------------------------------------
## input :
##          xmat   : matrix
## output : 
##          (1 x 1) log(det(xmat))
##
log_det = function(xmat) {
    return(c(determinant(xmat, logarithm = T)$modulus))
}



## preprocess() ----------------------------------------------------------------
## input :
##          post_samps : posterior samples from gamma(u), stored row-wise
##          D          : dimension of parameter
##          prior      : parameters to be passed into psi(), lambda()
## output : 
##          u_df       : dataframe w/ one more column than post_samps, contains
##                       psi(u) evalued for each posterior sample
##
preprocess = function(post_samps, D, prior) {
    
    psi_u = apply(post_samps, 1, psi, prior = prior) %>% unname() # (J x 1)
    
    # (1.2) name columns so that values can be extracted by partition.R
    u_df_names = character(D + 1)
    for (d in 1:D) {
        u_df_names[d] = paste("u", d, sep = '')
    }
    u_df_names[D + 1] = "psi_u"
    
    # populate u_df
    u_df = cbind(post_samps, psi_u) # J x (D + 1)
    names(u_df) = u_df_names
    
    
    return(u_df)
    
} # end of preprocess() function



# param_out is the return of u_star
plotPartition = function(u_df, param_out) {
    
    plot(u_df[,1], u_df[,2], pch = 20, cex = 1, col = "cyan",
         xlab = 'u1', ylab = 'u2', main = '')
    rect(param_out$u1_lb, 
         param_out$u2_lb, 
         param_out$u1_ub, 
         param_out$u2_ub)
    
    # add psi_hat labels for each partition
    text(x = param_out$u1_lb + (param_out$u1_ub - param_out$u1_lb) / 2, 
         y = param_out$u2_lb + (param_out$u2_ub - param_out$u2_lb) / 2,
         labels = round(param_out$psi_hat, 5),
         cex = 0.8)
    
    # make the 'median' points red and large
    points(x = param_out$u1_star, y = param_out$u2_star,
           col = 'red', pch = 19, cex = 1.2)
    
}


extractSupport = function(u_df, D) {
    
    # (3.1) obtain the (data-defined) support for each of the parameters
    param_support = matrix(NA, D, 2) # store the parameter supports row-wise
    
    for (d in 1:D) {
        param_d_min = min(u_df[,d])
        param_d_max = max(u_df[,d])
        
        param_support[d,] = c(param_d_min, param_d_max)
    }
    
    return(param_support)
}



# log_sum_exp():
# calculates expressions of the form log(sum(exp(x)))
log_sum_exp = function(x) { 
    offset = max(x)                         # scale by max to prevent overflow
    s = log(sum(exp(x - offset))) + offset
    i = which(!is.finite(s))                # check for any overflow
    if (length(i) > 0) {                    # replace inf values with max
        s[i] = offset 
    }
    
    return(s)
} # end of log_sum_exp()



# log_int_rect(): 
# compute the log of the closed form integral over the d-th rectangle
# note: we don't compute the integral explicitly b/c we use log-sum-exp at the
# end of the calculation for stability
log_int_rect = function(l_d, a, b) {
    
    # equivalent to the following calculation:
    # - l_k[d] * upper + 
    #     log(- 1 / l_k[d] * (1 - exp(-l_k[d] * lower + l_k[d] * upper)))
    
    # split into cases depending on the sign of the gradient (lambda_d)
    # note: 'lambda' is already the name of a the gradient function
    
    if (l_d > 0) {
        
        # extract e^(-lambda_d * a), term corresponding to the lower bound
        out = - l_d * a - log(l_d) + log1mexp(l_d * b - l_d * a)
        
    } else {
        
        # extract e^(-lambda_d * b), term corresponding to the upper bound
        out = - l_d * b - log(-l_d) + log1mexp(l_d * a - l_d * b)
        
    }
    
    return(out)
    
} # end of log_int_rect() function






## hml() -----------------------------------------------------------------------
## input :
##          N_approx   : # of approximations to form
##          D          : dimension of parameter
##          u_df_full  : (N_approx * J) x (D + 1) posterior samples, u,  and 
##                       psi(u) stored row-wise -- to be fed into rpart()
##          J          : # of MC samples to use PER APPROXIMATION
##          prior      : parameters to be passed into psi(), lambda()
## output : 
##          def_approx : (N_approx x 1) vector of approximations of LIL
##
hml = function(N_approx, D, u_df_full, J, prior) {
    
    const_vec  = numeric(N_approx) # store constant approximation
    taylor_vec = numeric(N_approx) # store taylor approximation
    hybrid_vec = numeric(N_approx) # store hybrid approximation
    
    # log-sum-exp version of approximation -- should match taylor_Vec
    # const_vec_lse = numeric(N_approx)
    # taylor_vec_lse = numeric(N_approx) 
    # hybrid_vec_lse = numeric(N_approx)
    
    # compute approximation to LIL N_approx times
    for (t in 1:N_approx) {
        
        # if (t %% 10 == 0) {
        #     print(paste("iter", t))
        # }
        
        ## (1) subset out rows in u_df_full to be used in the t-th approximation
        row_id = J * (t - 1) + 1
        u_df = u_df_full[row_id:(row_id+J-1),]
        
        ## (2) fit the regression tree via rpart()
        u_rpart = rpart(psi_u ~ ., u_df)
        
        ## (3) process the fitted tree
        
        # (3.1) obtain the (data-defined) support for each of the parameters
        
        param_support = extractSupport(u_df, D)
        
        # (3.2) obtain the partition
        u_partition = extractPartition(u_rpart, param_support)  # partition.R
        
        # organize all data into single data frame --> ready for approximation
        param_out = u_star(u_rpart, u_df, u_partition, D)
        
        # print(param_out)
        
        n_partitions = nrow(u_partition)     # number of partitions 
        # c_k        = numeric(n_partitions) # constant term for k-th partition
        # zhat       = numeric(n_partitions) # integral over k-th partition
        
        
        # ----------------------------------------------------------------------
        
        K = nrow(u_partition)
        
        
        # new declarations here: additional storage for all 3 approximations
        # area_k         = rep(1, K)      # store the area of each partition
        
        const_approx   = numeric(K)     # store approx that uses 1-term taylor
        taylor_approx  = numeric(K)     # store approx that uses 2-term taylor
        hybrid_approx  = numeric(K)     # store approx that uses both
        
        # e_ck_1   = numeric(K)         # store first constant in taylor approx
        # e_ck_2   = numeric(K)         # store second constant in taylor approx
        
        # declare terms that will be used in the log-sum-exp trick
        eta_k = numeric(K) # log of the area of each partition A_k
        
        ck_1 = numeric(K)
        ck_2 = numeric(K)
        
        # taylor_approx_lse = numeric(K)
        # const_approx_lse  = numeric(K)
        
        lambda_k = data.frame(matrix(NA, K, D)) # store gradient at u_k_star
        # names(lambda_k) = c("lambda1", "lambda2")
        names(lambda_k) = paste("lambda", 1:D, sep = '')
        
        # store integral of e^(-lambda_k'u) over A_k
        # taylor2_integral = numeric(K) # not currently using
        
        
        # star_ind will be a vector of indices -- subsetting these out of 
        # param_out will give u_k = (u_k1, u_k2, ... , u_kD)
        star_ind = grep("_star", names(param_out)) 
        
        # ----------------------------------------------------------------------
        
        # (4) compute closed form integral over each partition
        for (k in 1:n_partitions) {
            
            # print(k)
            
            # extract "representative point" of the k-th partition
            u = param_out[k, star_ind] %>% unlist %>% unname
            
            # compute lambda_k : gradient of psi, evaluated at u_star
            l_k = lambda(u, prior)       # (D x 1) 
            lambda_k[k,] = l_k
            
            # constant terms in the taylor expansion, this is factored outside
            # of the D-dim integral, so it's outside of the following for loop
            # e_ck_1[k] = exp(-psi(u, prior))
            # e_ck_2[k] = exp(sum(l_k * u))
            
            
            # compute the following for log-sum-exp trick
            ck_1[k] = -psi(u, prior)
            ck_2[k] = sum(l_k * u)
            
            ck_3 = numeric(D)
            
            # ------------------------------------------------------------------
            
            
            # store each component of the D-dim integral 
            integral_d = numeric(D) # (D x 1)
            
            for (d in 1:D) {
                
                # find column id of the first lower bound
                col_id_lb = grep("u1_lb", names(param_out)) + 2 * (d - 1)
                col_id_ub = col_id_lb + 1
                
                # limits of integration, length of the interval for param d
                upper = param_out[k, col_id_ub]
                lower = param_out[k, col_id_lb]
                
                
                # update/compute the constant approximation
                # area_k[k] = area_k[k] * (upper - lower) # D-dim hypercube
                
                eta_k[k] = eta_k[k] + log(upper - lower)
                
                # d-th integral computed in closed form
                # integral_d[d] = - 1 / l_k[d] * 
                #     (exp(- l_k[d] * upper) - exp(- l_k[d] * lower)) 
                
                # ck_3[d] = log(- 1 / l_k[d] * 
                #                   (exp(- l_k[d] * upper) - 
                #                        exp(- l_k[d] * lower)))
                
                # ck_3[d] = - l_k[d] * upper + 
                #     log(- 1 / l_k[d] * 
                #             (1 - exp(-l_k[d] * lower + l_k[d] * upper)))
                
                # print(l_k[d])
                # print(lower)
                # print(upper)
                
                # print(d)
                
                ck_3[d] = log_int_rect(l_k[d], lower, upper)
                
                
                
            } # end of loop computing each of 1-dim integrals
            
            
            # compute constant approximation
            # const_approx[k] = e_ck_1[k] * area_k[k]
            
            # compute the D-dim integral (product of D 1-dim integrals)
            # zhat[k] = prod(c_k[k], integral_d)
            # taylor_approx[k] = e_ck_1[k] * e_ck_2[k] * prod(integral_d)
            
            const_approx[k]  = ck_1[k] + eta_k[k]
            taylor_approx[k] = ck_1[k] + ck_2[k] + sum(ck_3)
            
            
        } # end of for loop over the K partitions
        
        # update approximations
        const_vec[t]  = log_sum_exp(const_approx) 
        taylor_vec[t] = log_sum_exp(taylor_approx)
        
        ## stack columns so that we can look more deeply into the integrals over
        ## each partition
        all_integrals = cbind(const  = const_approx, 
                              taylor = taylor_approx) 
        
        # in order to form the dataframes below, need to store lambda_k matrix        
        # diagnostics = all_integrals %>% cbind(lambda_k) %>% cbind(e_ck_2) 
        diagnostics = all_integrals %>% cbind(lambda_k)
        
        # diagnostics = all_integrals %>% cbind(lambda_k) %>% cbind(e_ck_2) %>%
        #     cbind(taylor2_int = taylor2_integral)
        
        # return(diagnostics)
        
        # TODO: to avoid computing this thing every time we need an approx, 
        # subset out the leaf id, constant approximations into a separate,
        # smaller dataframe
        verbose_partition = (param_out %>% 
                                 mutate(perc_mem = n_obs / sum(n_obs))) %>% 
            cbind(diagnostics) %>% arrange(desc(perc_mem))
        
        # add leaf id to each of the posterior samples
        # create columns for psi_tilde, as approximated by (1) constant, 
        # (2) order 1 taylor
        u_df = u_df %>% mutate(leaf_id = u_rpart$where, 
                               const_approx = 0,  const_resid = 0, 
                               taylor_approx = 0, taylor_resid = 0)
        
        partition_id = u_rpart$where %>% unique
        
        # for each partition, compute the sum of squared residuals, 
        # (psi(u) - psi_tilde(u))^2
        for (j in 1:K) {
            
            k = partition_id[j]
            
            u_k_star = param_out %>% filter(leaf_id == k) %>% 
                dplyr::select(star_ind) %>% unname %>% unlist
            
            #### compute constant approximation for psi
            # note: we actually already do this when computing e_ck_1, so 
            # eventually, we can just take log(e_ck_1) to recover this term
            u_df[u_df$leaf_id == k,]$const_approx = psi(u_k_star, prior) %>% c()
            
            #### compute order 1 taylor approximation for psi
            
            # assumes u1,...,uD are the first D columns of u_df -- make sure
            # this structure is maintained, maybe provide a check ? 
            diff_k = sweep(u_df %>% filter(leaf_id == k) %>% 
                               dplyr::select(c(1:D)), 2, 
                           FUN = '+', -u_k_star)
            
            # methodology notes: 
            # compute psi(u_star) for each of the partitions; we do this in 2
            # ways -> (1) constant approximation, (2) order 1 taylor
            # based on the residual for each approximation, we decide
            # which approximation to use to compute the integral over each 
            # partition
            u_df[u_df$leaf_id == k,]$taylor_approx = c(psi(u_k_star, prior)) + 
                as.matrix(diff_k) %*% lambda(u_k_star, prior)
            
            # compute difference between psi_u and corresponding approximation
            u_df = u_df %>% mutate(const_resid  = psi_u - const_approx,
                                   taylor_resid = psi_u - taylor_approx)
            
        } # end of for loop computing residuals
        
        
        # error_df -- dataframe that contains 
        #     (1) partition id 
        #     (2) squared residual associated with the constant approx
        #     (3) squared residual associated with the order 1 taylor approx
        error_df = data.frame(leaf_id = partition_id, 
                              const_sq_error = 0, taylor_sq_error = 0)
        
        for (i in 1:K) {
            
            k = partition_id[i]
            
            # compute squared residual for each approx method
            sse_const  = sum(u_df[u_df$leaf_id == k,]$const_resid^2)
            sse_taylor = sum(u_df[u_df$leaf_id == k,]$taylor_resid^2)
            
            # compute the SUM of squared residuals for each approx method
            error_df = error_df %>% 
                mutate(const_sq_error = replace(const_sq_error, 
                                                partition_id == k, 
                                                sse_const),
                       taylor_sq_error = replace(taylor_sq_error, 
                                                 partition_id == k,
                                                 sse_taylor))
            
        } # end of loop computing sum of squared residuals
        
        
        #### for each partition, determine which approximation to use
        
        # visualize the approximations side by side with associated SSE
        partition_approx = verbose_partition %>% 
            dplyr::select(leaf_id, const, taylor)
        
        partition_approx = merge(partition_approx, error_df, by = "leaf_id")
        
        # extract leaf id for which we use the taylor approximation
        taylor_index = error_df %>% filter(taylor_sq_error < const_sq_error) %>% 
            dplyr::select(leaf_id) %>% unlist %>% unname
        
        # extract leaf id for which we use the constant approximation
        const_index = error_df %>% filter(taylor_sq_error >= const_sq_error) %>% 
            dplyr::select(leaf_id) %>% unlist %>% unname
        
        # select the rows that correspond to the partitions for which we use 
        # constant approximation
        const_contribution = verbose_partition %>% 
            filter(leaf_id %in% const_index) %>% 
            dplyr::select(const) %>% unlist %>% unname
        
        # select the rows that correspond to the partitions for which we use 
        # taylor approximation
        taylor_contribution = verbose_partition %>% 
            filter(leaf_id %in% taylor_index) %>% 
            dplyr::select(taylor) %>% unlist %>% unname
        
        # merge contributions to form the final approximation
        if (length(taylor_contribution)[1] == 0) {
            hybrid_approx = log_sum_exp(const_contribution)
        } else if (length(const_contribution)[1] == 0) {
            hybrid_approx = log_sum_exp(taylor_contribution)
        } else {
            hybrid_approx = log_sum_exp(c(const_contribution, 
                                          taylor_contribution))
        }
        
        hybrid_vec[t] = hybrid_approx
        
    } # end of N_approx outer loop
    
    return(list(const_vec         = const_vec, 
                taylor_vec        = taylor_vec, 
                hybrid_vec        = hybrid_vec,
                verbose_partition = verbose_partition,
                partition         = param_out,
                n_taylor          = length(taylor_contribution),
                n_const           = length(const_contribution),
                error             = partition_approx,
                u_rpart           = u_rpart,
                taylor_approx     = taylor_approx,
                ck_2              = ck_2,
                ck_3              = ck_3,
                lambda_k          = lambda_k,
                u_df_star         = u_df))
    
} # end of hml() function
