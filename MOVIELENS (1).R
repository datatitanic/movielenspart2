#Jennifer Young

#Movie Recommendation Project

#Recommendation systems are used more and more, as consumers expect suggestions based
#on their known likes so that they can discover new likes in products, movies, music 
#and other interests. They assist users in finding what they might be interested in 
#based on their preferences and previous interactions. In this report, a movie 
#recommendation system using the MovieLens dataset from HarvardX’s Data Science 
#Professional Certificate3 program will be covered. GroupLens Research is the 
#organization that collected the data sets for this project from their site: 
#(https://movielens.org).

install.packages("scales")
install.packages("tidyverse")
install.packages("caret")
install.packages("data.table")
install.packages("lubridate")
install.packages("recosystem")
install.packages("kableExtra")
install.packages("devtools")
install.packages("Rcpp")
update.packages()
library(scales)
library(tidyverse)
library(dplyr)
library(caret)
library(data.table)
library(lubridate)
library(stringr)
library(recosystem)
library(kableExtra)
library(tinytex)
library(ggplot2)

library(Rcpp)

dl <- tempfile()
download.file("http://files.grouplens.org/datasets/movielens/ml-10m.zip", dl)
ratings <- read.table(text = gsub("::", "\t", readLines(unzip(dl, "ml-10M100K/ratings.dat"))),
                      col.names = c("userId", "movieId", "rating", "timestamp"))
movies <- str_split_fixed(readLines(unzip(dl, "ml-10M100K/movies.dat")), "\\::", 3)
colnames(movies) <- c("movieId", "title", "genres")
movies <- as.data.frame(movies) %>% mutate(movieId = as.integer(movieId),
                                           title = as.character(title),
                                           genres = as.character(genres))
movielens <- left_join(ratings, movies, by = "movieId")

#Methods and Analysis

#There are five steps in the data analysis process that must be completed. 
#In this case, the data must be prepared. The dataset from was downloaded from 
#the MovieLens website and split into two subsets used for training and validation. 
#In this case, we named the training set “edx” and the validation set “validation”. 
#For training and testing, the edx set was split again into two subsets. 
#The edx set is trained with the model when it reaches the RMSE goal and the 
#validation set is used for final validation. During data exploration and 
#visualization, charts are crated to understand the data and how it affects 
#the outcome. We observe the mean of observed values, the distribution of ratings,#
#mean movie ratings, movie effect, user effect and number of ratings per movie. 
#We improve the RMSE by including the user and movie effects and applying the 
#regularization parameter for samples that have few ratings.

# The Validation subset will be 10% of the MovieLens data.

set.seed(1)
test_index <- createDataPartition(y = movielens$rating, times = 1, p = 0.1, list = FALSE)
edx <- movielens[-test_index,]
temp <- movielens[test_index,]

#Make sure userId and movieId in validation set are also in edx subset:

validation <- temp %>%
  semi_join(edx, by = "movieId") %>%
  semi_join(edx, by = "userId")

# Add rows removed from validation set back into edx set

removed <- anti_join(temp, validation)
edx <- rbind(edx, removed)
rm(dl, ratings, movies, test_index, temp, movielens, removed)

# lists six variables “userID”, “movieID”, “rating”, “timestamp”, “title”, and “genres” in data frame 

head(edx) %>%
  print.data.frame()

dim(edx)
n_distinct(edx$movieId) # 10677
n_distinct(edx$title) # 10676: there might be movies of different IDs with the same title
n_distinct(edx$userId) # 69878
n_distinct(edx$movieId)*n_distinct(edx$userId) # 746087406
n_distinct(edx$movieId)*n_distinct(edx$userId)/dim(edx)[1] # 83

#Looking for missing values

summary(edx)

#unique movies and users in the edx subset

edx %>%
  summarize(n_users = n_distinct(userId), 
            n_movies = n_distinct(movieId))

#Extracting age of movies at rating
#Every movie was released in a certain year, which is provided in the title of the movie. Every user rated a movie in a certain year, which is included in the timestamp information. I define the difference between these two years, i.e., how old the movie was when it was watched/rated by a user, as the age of movies at rating. From the original dataset, I first exacted the rating year (year_rated) from timestamp, and then exacted the release year (year_released) of the movie from the title. age_at_rating was later calculated.

# convert timestamp to year
edx_1 <- edx %>% mutate(year_rated = year(as_datetime(timestamp)))
# extract the release year of the movie
# edx_1 has year_rated, year_released, age_at_rating, and titles without year information
edx_1 <- edx_1 %>% mutate(title = str_replace(title,"^(.+)\\s\\((\\d{4})\\)$","\\1__\\2" )) %>% 
  separate(title,c("title","year_released"),"__") %>%
  select(-timestamp) 
edx_1 <- edx_1 %>% mutate(age_at_rating= as.numeric(year_rated)-as.numeric(year_released))
head(edx_1)

#Extracting the genres information
#The genres information was provided in the original dataset as a combination of different classifications. For example (see above output), the movie “Boomerang” (movieId 122) was assigned “Comedy|Romance”, and “Flintstones, The” (movieId 355) is “Children|Comedy|Fantasy”. Both are combinations of different ones, while they actually share one genre (Comedy). It’ll make more sense if we first split these combinations into single ones:
  
  # edx_2: the mixture of genres is split into different rows
  edx_2 <- edx_1 %>% separate_rows(genres,sep = "\\|") %>% mutate(value=1)
n_distinct(edx_2$genres)  # 20: there are 20 differnt types of genres
genres_rating <- edx_2 %>% group_by(genres) %>% summarize(n=n())
genres_rating

edx_3 <- edx_2 %>% spread(genres, value, fill=0) %>% select(-"(no genres listed)")
dim(edx_3)
head(edx_3)

#The dataset actually duplicated each record into multiple ones, depending on the combination of the genres for each movie.
#We need to split into multiple columns to indicate different combinations of the 19 basic genres by spreading genres to the “wide” format:

#distribution of ratings (histogram)

edx %>%
  ggplot(aes(rating)) +
  geom_histogram(binwidth = 0.25, color = "red") +
  scale_x_discrete(limits = c(seq(0.5,5,0.5))) +
  scale_y_continuous(breaks = c(seq(0, 3000000, 500000))) +
  ggtitle("Rating distribution")

#ratingspermovie (Histogram)

edx %>%
  count(movieId) %>%
  ggplot(aes(n)) +
  geom_histogram(bins = 25, color = "yellow") +
  scale_x_log10() +
  xlab("Number of ratings") +
  ylab("Number of movies") +
  ggtitle("Number of ratings per movie")

#movies rated once (chart)

edx %>%
  group_by(movieId) %>%
  summarize(count = n()) %>%
  filter(count == 1) %>%
  left_join(edx, by = "movieId") %>%
  group_by(title) %>%
  summarize(rating = rating, n_rating = count) %>%
  slice(1:20) %>%
  knitr::kable()

#User ratings (Histogram)
edx %>%
  count(userId) %>%
  ggplot(aes(n)) +
  geom_histogram(bins = 25, color = "green") +
  scale_x_log10() +
  xlab("Number of ratings") + 
  ylab("Number of users") +
  ggtitle("Number of ratings given by users")

#Mean user ratings

edx %>%
  group_by(userId) %>%
  filter(n() >= 100) %>%
  summarize(b_u = mean(rating)) %>%
  ggplot(aes(b_u)) +
  geom_histogram(bins = 25, color = "white") +
  xlab("Mean rating") +
  ylab("Number of users") +
  ggtitle("Mean movie ratings given by users") +
  scale_x_discrete(limits = c(seq(0.5,5,0.5))) +
  theme_light()

#compute the RMSE

RMSE <- function(true_ratings, predicted_ratings){
  sqrt(mean((true_ratings - predicted_ratings)^2))
}

mu <- mean(edx$rating)
mu

naive_rmse <- RMSE(validation$rating, mu)
naive_rmse

rmse_results <- data_frame(Model = "Basic Average", RMSE = naive_rmse)
rmse_results

#age bias distribution
age_effect<- edx_1 %>% 
  group_by(age_at_rating) %>%
  summarize(b_a = mean(rating)-mu)
age_effect %>% qplot(b_a, geom ="histogram", bins = 10, data = ., color = I("magenta"))

validation_1 <- validation %>% 
  mutate(year_rated = year(as_datetime(timestamp)))%>% 
  mutate(title = str_replace(title,"^(.+)\\s\\((\\d{4})\\)$","\\1__\\2" )) %>% 
  separate(title,c("title","year_released"),"__") %>%
  select(-timestamp) %>%
  mutate(age_at_rating= as.numeric(year_rated)-as.numeric(year_released))

predicted_ratings_2 <- mu + validation_1 %>% 
  left_join(age_effect, by='age_at_rating') %>%
  pull(b_a)
model_2_rmse <- RMSE(validation$rating,predicted_ratings_2) # 1.05239
rmse_results <- bind_rows(rmse_results,
                          data_frame(Model="Age Effect Model",  
                                     RMSE = model_2_rmse))
rmse_results

#Age Effect Model did not improve the RMSE muchso it will not be used as a predictor.

#Now we are adding movie effects to the model

movie_avgs <- edx %>% 
  group_by(movieId) %>% 
  summarize(b_i = mean(rating - mu))
movie_avgs %>% qplot(b_i, geom ="histogram", bins = 10, data = ., color = I("green"))

predicted_ratings_3 <- mu + validation %>% 
  left_join(movie_avgs, by='movieId') %>%
  pull(b_i)
model_3_rmse <- RMSE(validation$rating,predicted_ratings_3) 
rmse_results <- bind_rows(rmse_results,
                          data_frame(Model="Movie Effect Model",  
                                     RMSE = model_3_rmse))
rmse_results

#The Movie Effect Model brought the RMSE under 1

#Now we add the bias of the user.  

user_avgs <- edx %>% 
  left_join(movie_avgs, by='movieId') %>%
  group_by(userId) %>%
  summarize(b_u = mean(rating - mu - b_i))
predicted_ratings_4 <- validation %>% 
  left_join(movie_avgs, by='movieId') %>%
  left_join(user_avgs, by='userId') %>%
  mutate(pred = mu + b_i + b_u) %>%
  pull(pred)
model_4_rmse <- RMSE(validation$rating,predicted_ratings_4)
rmse_results <- bind_rows(rmse_results,
                          data_frame(Model="User Effects Model+Movie Effect Model",  
                                     RMSE = model_4_rmse))
rmse_results

#Adding user bias further improves the RMSE. However, Regularization technique should be used to take into account the number of ratings made for a specific movie, by adding a larger penalty to estimates from smaller samples. Lambda will be used to do this. Cross validation within the test set can be performed to optimize this parameter before being applied to the validation set.
#In this case, we are doing this for movie effects only

# use 10-fold cross validation to pick a lambda for movie effects regularization
# split the data into 10 parts
set.seed(2019)
cv_splits <- createFolds(edx$rating, k=10, returnTrain =TRUE)

# define a matrix to store the results of cross validation
rmses <- matrix(nrow=10,ncol=51)
lambdas <- seq(0, 5, 0.1)

# perform 10-fold cross validation to determine the optimal lambda
for(k in 1:10) {
  train_set <- edx[cv_splits[[k]],]
  test_set <- edx[-cv_splits[[k]],]
  
  # Make sure userId and movieId in test set are also in the train set
  test_final <- test_set %>% 
    semi_join(train_set, by = "movieId") %>%
    semi_join(train_set, by = "userId")
  
  # Add rows removed from validation set back into edx set
  removed <- anti_join(test_set, test_final)
  train_final <- rbind(train_set, removed)
  
  mu <- mean(train_final$rating)
  just_the_sum <- train_final %>% 
    group_by(movieId) %>% 
    summarize(s = sum(rating - mu), n_i = n())
  
  rmses[k,] <- sapply(lambdas, function(l){
    predicted_ratings <- test_final %>% 
      left_join(just_the_sum, by='movieId') %>% 
      mutate(b_i = s/(n_i+l)) %>%
      mutate(pred = mu + b_i) %>%
      pull(pred)
    return(RMSE(predicted_ratings, test_final$rating))
  })
}

rmses_cv <- colMeans(rmses)
qplot(lambdas,rmses_cv)
lambda <- lambdas[which.min(rmses_cv)]

mu <- mean(edx$rating)
movie_reg_avgs <- edx %>% 
  group_by(movieId) %>% 
  summarize(b_i = sum(rating - mu)/(n()+lambda), n_i = n()) 
predicted_ratings_5 <- validation %>% 
  left_join(movie_reg_avgs, by = "movieId") %>%
  mutate(pred = mu + b_i) %>%
  pull(pred)
model_5_rmse <- RMSE(predicted_ratings_5, validation$rating)   # 0.943852 not too much improved
rmse_results <- bind_rows(rmse_results,
                          data_frame(Model="Regularized Movie Effect Model",  
                                     RMSE = model_5_rmse))
rmse_results 

#This model did not improve the RMSE.  

#This time,we will use the same lambdas for both movie and user effects.

# define a matrix to store the results of cross validation
lambdas <- seq(0, 8, 0.1)
rmses_2 <- matrix(nrow=10,ncol=length(lambdas))
# perform 10-fold cross validation to determine the optimal lambda
for(k in 1:10) {
  train_set <- edx[cv_splits[[k]],]
  test_set <- edx[-cv_splits[[k]],]
  
  # Make sure userId and movieId in test set are also in the train set
  test_final <- test_set %>% 
    semi_join(train_set, by = "movieId") %>%
    semi_join(train_set, by = "userId")
  
  # Add rows removed from validation set back into edx set
  removed <- anti_join(test_set, test_final)
  train_final <- rbind(train_set, removed)
  
  mu <- mean(train_final$rating)
  
  rmses_2[k,] <- sapply(lambdas, function(l){
    b_i <- train_final %>% 
      group_by(movieId) %>%
      summarize(b_i = sum(rating - mu)/(n()+l))
    b_u <- train_final %>% 
      left_join(b_i, by="movieId") %>%
      group_by(userId) %>%
      summarize(b_u = sum(rating - b_i - mu)/(n()+l))
    predicted_ratings <- 
      test_final %>% 
      left_join(b_i, by = "movieId") %>%
      left_join(b_u, by = "userId") %>%
      mutate(pred = mu + b_i + b_u) %>%
      pull(pred)
    return(RMSE(predicted_ratings, test_final$rating))
  })
}

rmses_2
rmses_2_cv <- colMeans(rmses_2)
rmses_2_cv
qplot(lambdas,rmses_2_cv)
lambda <- lambdas[which.min(rmses_2_cv)]   
#From the 10-fold cross validation, we get an optimized value of lambda: 4.9.


#Regularized User Effects Model+Movie Effect Model
#Now we use this parameter lambda to predict the validation dataset and evaluate the RMSE.

mu <- mean(edx$rating)
b_i_reg <- edx %>% 
  group_by(movieId) %>%
  summarize(b_i = sum(rating - mu)/(n()+lambda))
b_u_reg <- edx %>% 
  left_join(b_i_reg, by="movieId") %>%
  group_by(userId) %>%
  summarize(b_u = sum(rating - b_i - mu)/(n()+lambda))
predicted_ratings_6 <- 
  validation %>% 
  left_join(b_i_reg, by = "movieId") %>%
  left_join(b_u_reg, by = "userId") %>%
  mutate(pred = mu + b_i + b_u) %>%
  pull(pred)
model_6_rmse <- RMSE(predicted_ratings_6, validation$rating)  
rmse_results <- bind_rows(rmse_results,
                          data_frame(Model="Regularized User Effects Model+Movie Effect Model",  
                                     RMSE = model_6_rmse))
rmse_results 

#There is a slight improvement here.  

#Let's see what matrix factorization does on the regularized Movie + User Effect Model because it gives the lowest RMSE. 
#At this point, we need to calculate the residual. We need to still use the training set edx. 

lambda <- 4.9
mu <- mean(edx$rating)
b_i_reg <- edx %>% 
  group_by(movieId) %>%
  summarize(b_i = sum(rating - mu)/(n()+lambda))
b_u_reg <- edx %>% 
  left_join(b_i_reg, by="movieId") %>%
  group_by(userId) %>%
  summarize(b_u = sum(rating - b_i - mu)/(n()+lambda))
predicted_ratings_6_edx <- 
  edx %>% 
  left_join(b_i_reg, by = "movieId") %>%
  left_join(b_u_reg, by = "userId") %>%
  mutate(pred = mu + b_i + b_u) %>%
  pull(pred)
model_6_rmse_edx <- RMSE(predicted_ratings_6_edx, edx$rating)
model_6_rmse_edx


lambda <- 4.9
mu <- mean(edx$rating)
b_i_reg <- edx %>% 
  group_by(movieId) %>%
  summarize(b_i = sum(rating - mu)/(n()+lambda))
b_u_reg <- edx %>% 
  left_join(b_i_reg, by="movieId") %>%
  group_by(userId) %>%
  summarize(b_u = sum(rating - b_i - mu)/(n()+lambda))
predicted_ratings_6_edx <- 
  edx %>% 
  left_join(b_i_reg, by = "movieId") %>%
  left_join(b_u_reg, by = "userId") %>%
  mutate(pred = mu + b_i + b_u) %>%
  pull(pred)
model_6_rmse_edx <- RMSE(predicted_ratings_6_edx, edx$rating)
model_6_rmse_edx

edx_residual <- edx %>% 
  left_join(b_i_reg, by = "movieId") %>%
  left_join(b_u_reg, by = "userId") %>%
  mutate(residual = rating - mu - b_i - b_u) %>%
  select(userId, movieId, residual)
head(edx_residual)

# as matrix
edx_for_mf <- as.matrix(edx_residual)
validation_for_mf <- validation %>% 
  select(userId, movieId, rating)
validation_for_mf <- as.matrix(validation_for_mf)

# write edx_for_mf and validation_for_mf tables on disk
write.table(edx_for_mf , file = "trainset.txt" , sep = " " , row.names = FALSE, col.names = FALSE)
write.table(validation_for_mf, file = "validset.txt" , sep = " " , row.names = FALSE, col.names = FALSE)

# use data_file() to specify a data set from a file in the hard disk.
set.seed(2019) 
train_set <- data_file("trainset.txt")
valid_set <- data_file("validset.txt")

# build a recommender object
r <-Reco()

# tuning training set
opts <- r$tune(train_set, opts = list(dim = c(10, 20, 30), lrate = c(0.1, 0.2),
                                      costp_l1 = 0, costq_l1 = 0,
                                      nthread = 1, niter = 10))
opts

r$train(train_set, opts = c(opts$min, nthread = 1, niter = 20))

# Making prediction on validation set and calculating RMSE:
pred_file <- tempfile()
r$predict(valid_set, out_file(pred_file))  
predicted_residuals_mf <- scan(pred_file)
predicted_ratings_mf <- predicted_ratings_6 + predicted_residuals_mf
rmse_mf <- RMSE(predicted_ratings_mf,validation$rating) 
rmse_results <- bind_rows(rmse_results,
                          data_frame(Model="Matrix Factorization",  
                                     RMSE = rmse_mf))
rmse_results 


#Results
#For the average movie rating model that we generated first, the result was 1.0606506. 
#After accounting for movie effects, we lowered the average to .944. In order to lower 
#the RMSE even more, we added both the movie and user effects with the result of .866 
#We used regularization to penalize samples with few ratings and got a result of .94.  We continued 
#with adding user effects and reduced the RMSE to .865. # Finally, we used matrix factorization to get the lowest RMSE of .787

#Conclusion
#In conclusion, we downloaded the data set and prepared it for analysis. 
#We looked for various insights and created a simple model from the mean of the 
#observed ratings. After that, we added the movie and user effects in an attempt 
#to model user behavior. Finally, we conducted regularization that added a 
#penalty for the movies and users with the least number of ratings. We achieved 
#a model with an RMSE of 0.865.  We decided to conduct matrix factorization on the lowest RMSE, 
#which occured when we calculated the RMSE in model 6, which was the  Regularized Movie + User Effect Model.

print("Operating System:")
version
```