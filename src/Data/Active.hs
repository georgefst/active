{-# LANGUAGE DeriveFunctor
           , GeneralizedNewtypeDeriving
           , TypeSynonymInstances
           , MultiParamTypeClasses
           , TypeFamilies
           , FlexibleInstances
  #-}
module Data.Active where

import Data.Array

import Data.Semigroup
import Data.Functor.Apply
import Control.Applicative
import Control.Newtype

import Data.VectorSpace hiding ((<.>))
import Data.AffineSpace

newtype Time = Time { unTime :: Rational }
  deriving ( Eq, Ord, Show, Read, Enum, Num, Fractional, Real, RealFrac
           , AdditiveGroup, InnerSpace
           )

instance Newtype Time Rational where
  pack   = Time
  unpack = unTime
  
instance VectorSpace Time where
  type Scalar Time = Rational
  s *^ (Time t) = Time (s * t)
  
newtype Duration = Duration { unDuration :: Rational }
  deriving ( Eq, Ord, Show, Read, Enum, Num, Fractional, Real, RealFrac
           , AdditiveGroup)
           
instance Newtype Duration Rational where
  pack   = Duration
  unpack = unDuration

instance AffineSpace Time where
  type Diff Time = Duration
  (Time t1) .-. (Time t2) = Duration (t1 - t2)
  (Time t) .+^ (Duration d) = Time (t + d)

newtype Era = Era (Min Time, Max Time)
  deriving (Semigroup)

mkEra :: Time -> Time -> Era
mkEra s e = Era (Min s, Max e)

start :: Era -> Time
start (Era (Min t, _)) = t

end :: Era -> Time
end (Era (_, Max t)) = t

duration :: Era -> Duration
duration = (.-.) <$> end <*> start

data Dynamic a = Dynamic { era        :: Era
                         , runDynamic :: Time -> a
                         }
  deriving (Functor)

instance Apply Dynamic where
  (Dynamic d1 f1) <.> (Dynamic d2 f2) = Dynamic (d1 <> d2) (f1 <.> f2)
  
instance Semigroup a => Semigroup (Dynamic a) where
  Dynamic d1 f1 <> Dynamic d2 f2 = Dynamic (d1 <> d2) (f1 <> f2)
  
newtype Active a = Active (MaybeApply Dynamic a)
  deriving (Functor, Apply, Applicative)

instance Newtype (Active a) (MaybeApply Dynamic a) where
  pack              = Active
  unpack (Active m) = m

instance Newtype (MaybeApply f a) (Either (f a) a) where
  pack   = MaybeApply
  unpack = runMaybeApply

over2 :: (Newtype n o, Newtype n' o', Newtype n'' o'')
      => (o -> n) -> (o -> o' -> o'') -> (n -> n' -> n'')
over2 _ f n1 n2 = pack (f (unpack n1) (unpack n2))

instance Semigroup a => Semigroup (Active a) where
  (<>) = (over2 Active . over2 MaybeApply) combine
   where
    combine (Right m1) (Right m2)
      = Right (m1 <> m2)

    combine (Left (Dynamic dur f)) (Right m)
      = Left (Dynamic dur (f <> const m))

    combine (Right m) (Left (Dynamic dur f))
      = Left (Dynamic dur (const m <> f))

    combine (Left d1) (Left d2)
      = Left (d1 <> d2)

instance (Monoid a, Semigroup a) => Monoid (Active a) where
  mempty = Active (MaybeApply (Right mempty))
  mappend = (<>)

mkActive :: Time -> Time -> (Time -> a) -> Active a
mkActive s e f
  = Active (MaybeApply (Left (Dynamic (mkEra s e) f)))

ui :: Active Double
ui = mkActive 0 1 (fromRational . unTime)

onActive :: (a -> b) -> (Dynamic a -> b) -> Active a -> b
onActive f _ (Active (MaybeApply (Right a))) = f a
onActive _ f (Active (MaybeApply (Left d)))  = f d

discrete :: [a] -> Active a
discrete [] = error "Data.Active.discrete must be called with a non-empty list."
discrete xs = f <$> ui
  where f t | t <= 0    = arr ! 0
            | t >= 1    = arr ! (n-1)
            | otherwise = arr ! floor (t * fromIntegral n)
        n   = length xs
        arr = listArray (0, n-1) xs

simulate :: Rational -> Active a -> [a]
simulate rate act =
  onActive (:[])
           (\d -> map (runDynamic d)
                      (let s = start (era d)
                           e = end   (era d)
                       in  [s, s + 1^/rate .. e]
                      )
           )
           act
