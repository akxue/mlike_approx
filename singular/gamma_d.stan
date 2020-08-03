//
// This Stan program defines a simple model, with a
// vector of values 'y' modeled as normally distributed
// with mean 'mu' and standard deviation 'sigma'.
//
// Learn more about model development with Stan at:
//
//    http://mc-stan.org/users/interfaces/rstan.html
//    https://github.com/stan-dev/rstan/wiki/RStan-Getting-Started
//


data {
  int<lower=0> N; // sample size
}


parameters {
  vector<lower=0, upper=1>[4] u;   // 2-dim parameter
}


model {
  // log prior
  // target += uniform_lpdf(u[1] | 0, 1) + uniform_lpdf(u[2] | 0, 1) + 
  // 	uniform_lpdf(u[3] | 0, 1) + uniform_lpdf(u[4] | 0, 1) + 
  // 	uniform_lpdf(u[5] | 0, 1) + uniform_lpdf(u[6] | 0, 1) + 
  // 	uniform_lpdf(u[7] | 0, 1) + uniform_lpdf(u[8] | 0, 1) + 
  // 	uniform_lpdf(u[9] | 0, 1) + uniform_lpdf(u[10] | 0, 1); 
  
  // target += -N * square(u[1]) * square(square(u[2])) * square(u[3]) * 
  //   square(u[4]) * square(u[5]) * square(u[6]) * square(u[7]) * square(u[8]) *
  //   square(u[9]) * square(u[10]);
  
  target += uniform_lpdf(u[1] | 0, 1) + uniform_lpdf(u[2] | 0, 1) +
  	uniform_lpdf(u[3] | 0, 1) + uniform_lpdf(u[4] | 0, 1);
  	
  target += -N * square(u[1]) * square(square(u[2])) * square(u[3]) *
    square(u[4]);

}
